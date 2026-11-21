module Main (main) where

import Control.Exception (IOException, evaluate, try)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure, ExitSuccess), exitWith)
import System.IO (hFlush, stdout)
import System.IO.Error (isEOFError)

import Motor.Comandos (interpretarComando)
import Motor.Mundo (leerMundo)
import Motor.Nucleo (ejecutar, estadoInicial, haGanado, mensajeErrorInicio)
import Motor.Persistencia
    ( cargarPartida
    , guardarPartida
    , mensajeErrorPartida
    )
import Motor.Tipos

main :: IO ()
main = do
    argumentos <- getArgs
    case argumentos of
        ["--validar", ruta] -> validar ruta
        [ruta] -> jugar ruta
        _ -> do
            putStrLn "Uso:"
            putStrLn "  aventura <archivo-de-mundo>"
            putStrLn "  aventura --validar <archivo-de-mundo>"
            exitWith (ExitFailure 1)

-- ---------------------------------------------------------------------------
-- Validación del mundo
-- ---------------------------------------------------------------------------

validar :: FilePath -> IO ()
validar ruta = do
    resultado <- cargarMundo ruta
    case resultado of
        Left detalle -> fallo detalle
        Right _ -> putStrLn "Mundo válido."

-- ---------------------------------------------------------------------------
-- Partida
-- ---------------------------------------------------------------------------

jugar :: FilePath -> IO ()
jugar ruta = do
    resultado <- cargarMundo ruta
    case resultado of
        Left detalle -> fallo detalle
        Right m ->
            case estadoInicial m of
                Left err -> fallo (mensajeErrorInicio err)
                Right e0 -> do
                    putStrLn ("*** " ++ nombre m ++ " ***")
                    mapM_ putStrLn (fst (ejecutar Mirar e0))
                    comprobarGanar m e0

bucle :: Mundo -> Estado -> IO ()
bucle m e = do
    putStr "> "
    hFlush stdout
    entrada <- try getLine :: IO (Either IOException String)
    case entrada of
        Left err
            | isEOFError err -> exitWith ExitSuccess
            | otherwise -> fallo ("Error al leer la entrada: " ++ show err)
        Right linea ->
            case interpretarComando linea of
                Left aviso -> do
                    putStrLn aviso
                    bucle m e
                Right comando -> manejar m e comando

-- | Los comandos que necesitan IO (guardar, cargar y salir) se atienden
-- aquí, antes de llamar a 'ejecutar'. Los demás son puros.
manejar :: Mundo -> Estado -> Comando -> IO ()
manejar m e comando = case comando of
    Salir -> do
        putStrLn "Hasta luego."
        exitWith ExitSuccess
    Guardar ruta -> do
        resultado <- guardarPartida m ruta e
        case resultado of
            Right () -> putStrLn ("Partida guardada en '" ++ ruta ++ "'.")
            Left err -> putStrLn (mensajeErrorPartida err)
        bucle m e
    Cargar ruta -> do
        resultado <- cargarPartida m ruta
        case resultado of
            Left err -> do
                putStrLn (mensajeErrorPartida err)
                bucle m e
            Right e' -> do
                putStrLn ("Partida cargada desde '" ++ ruta ++ "'.")
                mapM_ putStrLn (fst (ejecutar Mirar e'))
                comprobarGanar m e'
    _ -> do
        let (mensajes, e') = ejecutar comando e
        mapM_ putStrLn mensajes
        comprobarGanar m e'

comprobarGanar :: Mundo -> Estado -> IO ()
comprobarGanar m e
    | haGanado e = do
        putStrLn "*** ¡Has ganado! ***"
        exitWith ExitSuccess
    | otherwise = bucle m e

-- ---------------------------------------------------------------------------
-- Entrada del mundo
-- ---------------------------------------------------------------------------

cargarMundo :: FilePath -> IO (Either String Mundo)
cargarMundo ruta = do
    contenido <- leerTexto ruta
    pure $
        contenido >>= either
            (Left . unlines . map mostrarErrorMundo)
            Right
            . leerMundo

leerTexto :: FilePath -> IO (Either String String)
leerTexto ruta = do
    resultado <- try leerContenido :: IO (Either IOException String)
    pure $ case resultado of
        Left err ->
            Left ("No se pudo leer '" ++ ruta ++ "': " ++ show err)
        Right contenido -> Right contenido
  where
    leerContenido = do
        contenido <- readFile ruta
        _ <- evaluate (length contenido)
        pure contenido

mostrarErrorMundo :: ErrorMundo -> String
mostrarErrorMundo (ErrorSintaxis linea mensaje) =
    "línea " ++ show linea ++ ": " ++ mensaje
mostrarErrorMundo err = show err

fallo :: String -> IO a
fallo mensaje = do
    mapM_ (putStrLn . ("Error: " ++)) (lines mensaje)
    exitWith (ExitFailure 1)
