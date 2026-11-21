module Main (main) where

import Control.Exception (IOException, catch)
import Data.List (isInfixOf, sort)
import qualified Data.Map as Map
import Data.Maybe (mapMaybe)
import System.Directory (getTemporaryDirectory, removeFile)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>))
import Test.HUnit

import Motor.Comandos (interpretarComando, leerComando)
import Motor.Mundo (leerMundo)
import Motor.Nucleo
    ( ejecutar
    , estadoInicial
    , haGanado
    , mensajeErrorInicio
    )
import Motor.Persistencia
    ( ErrorPartida (..)
    , cargarPartida
    , deserializarPartida
    , guardarPartida
    , huellaMundo
    , mensajeErrorPartida
    , serializarPartida
    )
import Motor.Tipos

-- ---------------------------------------------------------------------------
-- Mundo de prueba
-- ---------------------------------------------------------------------------

textoBase :: String
textoBase =
    unlines
        [ "MUNDO: Base"
        , "INICIO: entrada"
        , "META: llevar llave a boveda"
        , "---"
        , "OBJETO: linterna"
        , "DESC: Una linterna."
        , "LUZ: si"
        , "---"
        , "OBJETO: llave"
        , "DESC: Una llave."
        , "---"
        , "SALA: entrada"
        , "DESC: La entrada."
        , "OBJETO: linterna"
        , "SALIDA: norte -> pasillo"
        , "---"
        , "SALA: pasillo"
        , "DESC: Un pasillo."
        , "SALIDA: sur -> entrada"
        , "SALIDA: este -> oscuro"
        , "SALIDA: norte -> boveda"
        , "SALIDA: oeste -> deposito requiere llave"
        , "---"
        , "SALA: oscuro"
        , "DESC: Un cuarto oscuro."
        , "OSCURA: si"
        , "OBJETO: llave"
        , "SALIDA: oeste -> pasillo"
        , "---"
        , "SALA: boveda"
        , "DESC: La boveda."
        , "SALIDA: sur -> pasillo"
        , "---"
        , "SALA: deposito"
        , "DESC: Un deposito."
        , "SALIDA: este -> pasillo"
        ]

-- | Mundo con un objeto colocado en dos salas (V7).
textoV7 :: String
textoV7 =
    unlines
        [ "MUNDO: V7"
        , "INICIO: a"
        , "META: llegar a a"
        , "---"
        , "OBJETO: x"
        , "DESC: X."
        , "---"
        , "SALA: a"
        , "DESC: A."
        , "OBJETO: x"
        , "SALIDA: norte -> b"
        , "---"
        , "SALA: b"
        , "DESC: B."
        , "OBJETO: x"
        , "SALIDA: sur -> a"
        ]

-- | Mundo cuyo objeto necesario para la meta no está en ninguna sala (V10).
textoV10 :: String
textoV10 =
    unlines
        [ "MUNDO: V10"
        , "INICIO: a"
        , "META: llevar llave a a"
        , "---"
        , "OBJETO: llave"
        , "DESC: Llave."
        , "---"
        , "SALA: a"
        , "DESC: A."
        ]

identificador :: String -> Identificador
identificador = Identificador

mundoDe :: String -> Mundo
mundoDe texto =
    case leerMundo texto of
        Right m -> m
        Left errs -> error ("Mundo de prueba invalido: " ++ show errs)

estadoDe :: String -> Estado
estadoDe texto =
    case estadoInicial (mundoDe texto) of
        Right e -> e
        Left err -> error ("Estado inicial invalido: " ++ show err)

mensajesDe :: Comando -> Estado -> [String]
mensajesDe cmd e = fst (ejecutar cmd e)

estadoTras :: [Comando] -> Estado -> Estado
estadoTras comandos e = foldl paso e comandos
  where
    paso actual cmd = snd (ejecutar cmd actual)

contiene :: String -> [String] -> Bool
contiene fragmento = any (fragmento `isInfixOf`)

objetosEn :: Identificador -> Estado -> [Identificador]
objetosEn sala e =
    case Map.lookup sala (salas (mundoActual e)) of
        Just s -> objetosSala s
        Nothing -> []

cambiarLinea :: String -> String -> String -> String
cambiarLinea vieja nueva =
    unlines . map reemplazar . lines
  where
    reemplazar linea
        | linea == vieja = nueva
        | otherwise = linea

conInicio :: String -> String -> String
conInicio sala = cambiarLinea "INICIO: entrada" ("INICIO: " ++ sala)

ignorarErrorIO :: IOException -> IO ()
ignorarErrorIO _ = pure ()

-- ---------------------------------------------------------------------------
-- Comandos
-- ---------------------------------------------------------------------------

testsComandos :: Test
testsComandos =
    TestList
        [ "leerComando: mirar" ~: leerComando "mirar" ~?= Just Mirar
        , "leerComando: sin distinguir mayusculas" ~:
            leerComando "  Tomar   Linterna " ~?= Just (Tomar (identificador "linterna"))
        , "leerComando: direccion sola" ~: leerComando "norte" ~?= Just (Ir Norte)
        , "leerComando: direccion en mayusculas" ~: leerComando "NORTE" ~?= Just (Ir Norte)
        , "leerComando: sinonimo coger" ~:
            leerComando "coger llave" ~?= Just (Tomar (identificador "llave"))
        , "leerComando: sinonimo inv" ~: leerComando "inv" ~?= Just Inventario
        , "leerComando: rechaza articulos" ~: leerComando "tomar la llave" ~?= Nothing
        , "leerComando: rechaza abreviaturas" ~: leerComando "n" ~?= Nothing
        , "leerComando: rechaza direccion con texto" ~: leerComando "norte extra" ~?= Nothing
        , "interpretarComando: linea vacia" ~: TestCase $
            case interpretarComando "   " of
                Left mensaje -> assertBool "habla de comandos" ("comando" `isInfixOf` mensaje)
                Right _ -> assertFailure "una linea vacia no es un comando"
        , "interpretarComando: comando desconocido" ~: TestCase $
            case interpretarComando "volar" of
                Left mensaje -> assertBool "dice no reconocido" ("no reconocido" `isInfixOf` mensaje)
                Right _ -> assertFailure "volar no es un comando"
        ]

-- ---------------------------------------------------------------------------
-- Reconocimiento y validacion del mundo
-- ---------------------------------------------------------------------------

testsMundo :: Test
testsMundo =
    TestList
        [ "leerMundo: mundo valido" ~: TestCase $
            case leerMundo textoBase of
                Left errs -> assertFailure ("errores inesperados: " ++ show errs)
                Right m -> do
                    assertEqual "salas" 5 (Map.size (salas m))
                    assertEqual "objetos" 2 (Map.size (objetos m))
                    assertEqual "inicio" (identificador "entrada") (inicio m)
                    assertEqual
                        "meta"
                        (LlevarA (identificador "llave") (identificador "boveda"))
                        (meta m)
        , "leerMundo: variante oscuridad" ~: TestCase $ do
            let m = mundoDe textoBase
            assertEqual
                "sala oscura"
                (Just True)
                (oscura <$> Map.lookup (identificador "oscuro") (salas m))
            assertEqual
                "objeto con luz"
                (Just True)
                (ilumina <$> Map.lookup (identificador "linterna") (objetos m))
        , "leerMundo: invalido_semantica reporta los 9 errores" ~: TestCase $ do
            texto <- readFile "mundos/invalido_semantica.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores semanticos"
                Left errs -> do
                    assertEqual "cantidad" 9 (length errs)
                    assertBool "V2" $
                        IdentificadorDuplicado EntidadObjeto (identificador "antorcha") `elem` errs
                    assertBool "V3 norte" $
                        SalidaASalaInexistente (identificador "vestibulo") Norte (identificador "sotano")
                            `elem` errs
                    assertBool "V3 este" $
                        SalidaASalaInexistente (identificador "vestibulo") Este (identificador "jardin")
                            `elem` errs
                    assertBool "V4" $
                        SalidaRequiereObjetoInexistente (identificador "vestibulo") Este (identificador "llave")
                            `elem` errs
                    assertBool "V5" $
                        SalidasMismaDireccion (identificador "vestibulo") Norte `elem` errs
                    assertBool "V6" $
                        SalaConObjetoNoDefinido (identificador "pasillo") (identificador "escudo")
                            `elem` errs
                    assertBool "V8 gema" $
                        ReferenciaGlobalInexistente ReferenciaMeta (identificador "gema") `elem` errs
                    assertBool "V8 torre" $
                        ReferenciaGlobalInexistente ReferenciaMeta (identificador "torre") `elem` errs
                    assertBool "V9" $
                        SalaInalcanzable (identificador "armeria") `elem` errs
        , "leerMundo: invalido_sintaxis reporta las lineas" ~: TestCase $ do
            texto <- readFile "mundos/invalido_sintaxis.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores de sintaxis"
                Left errs -> do
                    let numeros = [n | ErrorSintaxis n _ <- errs]
                    assertEqual "cantidad" 4 (length errs)
                    assertEqual "todas son de sintaxis" 4 (length numeros)
                    assertEqual "lineas" [4, 8, 9, 11] (sort numeros)
        , "leerMundo: V7 objeto en dos salas" ~: TestCase $
            case leerMundo textoV7 of
                Right _ -> assertFailure "se esperaba ObjetoMultiplesSalas"
                Left errs -> assertBool "V7" (ObjetoMultiplesSalas (identificador "x") `elem` errs)
        , "leerMundo: V10 objeto necesario sin colocar" ~: TestCase $
            case leerMundo textoV10 of
                Right _ -> assertFailure "se esperaba ObjetoNecesarioNoColocado"
                Left errs ->
                    assertBool "V10" (ObjetoNecesarioNoColocado (identificador "llave") `elem` errs)
        ]

-- ---------------------------------------------------------------------------
-- Nucleo del juego
-- ---------------------------------------------------------------------------

testsNucleo :: Test
testsNucleo =
    TestList
        [ "estadoInicial: sala e inventario" ~: TestCase $
            case estadoInicial (mundoDe textoBase) of
                Left err -> assertFailure ("error inesperado: " ++ show err)
                Right e -> do
                    assertEqual "sala" (identificador "entrada") (salaActual e)
                    assertEqual "inventario" [] (inventarioActual e)
        , "estadoInicial: rechaza inicio oscuro" ~:
            estadoInicial (mundoDe (conInicio "oscuro" textoBase))
                ~?= Left (SalaInicialOscura (identificador "oscuro"))
        , "estadoInicial: rechaza inicio inexistente" ~:
            let m = mundoDe textoBase
            in estadoInicial (m {inicio = identificador "fantasma"})
                ~?= Left (SalaInicialInexistente (identificador "fantasma"))
        , "mensajeErrorInicio: menciona la sala" ~: TestCase $
            assertBool
                "menciona la sala"
                ("oscuro" `isInfixOf` mensajeErrorInicio (SalaInicialOscura (identificador "oscuro")))
        , "mirar: descripcion, objetos y salidas" ~: TestCase $ do
            let mensajes = mensajesDe Mirar (estadoDe textoBase)
            assertBool "descripcion" (contiene "La entrada." mensajes)
            assertBool "objetos" (contiene "Objetos: linterna" mensajes)
            assertBool "salidas" (contiene "norte -> pasillo" mensajes)
        , "tomar: mueve el objeto al inventario" ~: TestCase $ do
            let e = estadoTras [Tomar (identificador "linterna")] (estadoDe textoBase)
            assertEqual "inventario" [identificador "linterna"] (inventarioActual e)
            assertBool
                "sale de la sala"
                (identificador "linterna" `notElem` objetosEn (identificador "entrada") e)
        , "soltar: devuelve el objeto a la sala" ~: TestCase $ do
            let e =
                    estadoTras
                        [Tomar (identificador "linterna"), Soltar (identificador "linterna")]
                        (estadoDe textoBase)
            assertEqual "inventario" [] (inventarioActual e)
            assertBool
                "vuelve a la sala"
                (identificador "linterna" `elem` objetosEn (identificador "entrada") e)
        , "tomar: objeto ausente no cambia nada" ~: TestCase $ do
            let e0 = estadoDe textoBase
                (mensajes, e1) = ejecutar (Tomar (identificador "llave")) e0
            assertEqual "estado" e0 e1
            assertBool "mensaje" (contiene "No hay llave" mensajes)
        , "ir: cambia de sala" ~: TestCase $ do
            let e = estadoTras [Ir Norte] (estadoDe textoBase)
            assertEqual "sala" (identificador "pasillo") (salaActual e)
        , "ir: salida inexistente" ~: TestCase $ do
            let e0 = estadoDe textoBase
                (mensajes, e1) = ejecutar (Ir Abajo) e0
            assertEqual "estado" e0 e1
            assertBool "mensaje" (contiene "No hay salida al abajo" mensajes)
        , "ir: salida bloqueada" ~: TestCase $ do
            let e0 = estadoTras [Ir Norte] (estadoDe textoBase)
                (mensajes, e1) = ejecutar (Ir Oeste) e0
            assertEqual "sala" (identificador "pasillo") (salaActual e1)
            assertBool "mensaje" (contiene "bloqueada" mensajes)
        , "ir: sala oscura sin luz" ~: TestCase $ do
            let e0 = estadoTras [Ir Norte] (estadoDe textoBase)
                (mensajes, e1) = ejecutar (Ir Este) e0
            assertEqual "sala" (identificador "pasillo") (salaActual e1)
            assertBool "mensaje" (contiene "oscura" mensajes)
        , "ir: sala oscura con luz" ~: TestCase $ do
            let e0 =
                    estadoTras
                        [Tomar (identificador "linterna"), Ir Norte]
                        (estadoDe textoBase)
                (_, e1) = ejecutar (Ir Este) e0
            assertEqual "sala" (identificador "oscuro") (salaActual e1)
        , "oscuridad: mirar y tomar bloqueados" ~: TestCase $ do
            let e = (estadoDe textoBase) {salaActual = identificador "oscuro"}
                (mirarMsgs, _) = ejecutar Mirar e
                (tomarMsgs, e1) = ejecutar (Tomar (identificador "llave")) e
            assertBool "mirar" (contiene "oscura" mirarMsgs)
            assertBool "tomar" (contiene "oscura" tomarMsgs)
            assertEqual "inventario" [] (inventarioActual e1)
        , "oscuridad: se puede salir de la sala" ~: TestCase $ do
            let e = (estadoDe textoBase) {salaActual = identificador "oscuro"}
                (_, e1) = ejecutar (Ir Oeste) e
            assertEqual "sala" (identificador "pasillo") (salaActual e1)
        , "examinar: objeto del inventario" ~: TestCase $ do
            let e = estadoTras [Tomar (identificador "linterna")] (estadoDe textoBase)
                (mensajes, _) = ejecutar (Examinar (identificador "linterna")) e
            assertBool "descripcion" (contiene "Una linterna." mensajes)
        , "inventario: vacio y con objetos" ~: TestCase $ do
            let e0 = estadoDe textoBase
            assertBool "vacio" (contiene "No llevas nada." (mensajesDe Inventario e0))
            let e1 = estadoTras [Tomar (identificador "linterna")] e0
            assertBool "con objeto" (contiene "Llevas: linterna" (mensajesDe Inventario e1))
        , "ayuda: menciona sinonimos y comandos" ~: TestCase $ do
            let mensajes = mensajesDe Ayuda (estadoDe textoBase)
            assertBool "coger" (contiene "coger" mensajes)
            assertBool "inv" (contiene "inv" mensajes)
            assertBool "guardar" (contiene "guardar" mensajes)
        ]

-- ---------------------------------------------------------------------------
-- Meta
-- ---------------------------------------------------------------------------

testsMeta :: Test
testsMeta =
    TestList
        [ "haGanado: falso al inicio" ~: haGanado (estadoDe textoBase) ~?= False
        , "haGanado: LlevarA verdadero" ~:
            let e =
                    (estadoDe textoBase)
                        { salaActual = identificador "boveda"
                        , inventarioActual = [identificador "llave"]
                        }
            in haGanado e ~?= True
        , "haGanado: LlevarA sin el objeto" ~:
            let e = (estadoDe textoBase) {salaActual = identificador "boveda"}
            in haGanado e ~?= False
        , "haGanado: LlegarA" ~:
            let m = mundoDe textoBase
                e =
                    (estadoDe textoBase)
                        { mundoActual = m {meta = LlegarA (identificador "boveda")}
                        , salaActual = identificador "boveda"
                        }
            in haGanado e ~?= True
        ]

-- ---------------------------------------------------------------------------
-- Persistencia
-- ---------------------------------------------------------------------------

testsPersistencia :: Test
testsPersistencia =
    TestList
        [ "persistencia: ida y vuelta" ~: TestCase $ do
            let m = mundoDe textoBase
                e0 = estadoDe textoBase
                e1 =
                    estadoTras
                        [ Tomar (identificador "linterna")
                        , Ir Norte
                        , Soltar (identificador "linterna")
                        ]
                        e0
            assertEqual
                "deserializar"
                (Right e1)
                (deserializarPartida m (serializarPartida m e1))
        , "persistencia: detecta mundo modificado" ~: TestCase $ do
            let m = mundoDe textoBase
                m' =
                    mundoDe
                        (cambiarLinea "DESC: La boveda." "DESC: La boveda secreta." textoBase)
                e = estadoDe textoBase
            assertEqual
                "mundo modificado"
                (Left MundoModificado)
                (deserializarPartida m' (serializarPartida m e))
        , "persistencia: rechaza partida corrupta" ~: TestCase $ do
            let m = mundoDe textoBase
            case deserializarPartida m "AVENTURA 1\nFIN\n" of
                Left (PartidaCorrupta _) -> pure ()
                otro -> assertFailure ("se esperaba PartidaCorrupta: " ++ show otro)
        , "persistencia: huella ignora comentarios" ~: TestCase $ do
            let m1 = mundoDe textoBase
                m2 = mundoDe ("# comentario nuevo\n" ++ textoBase)
            assertEqual "huella" (huellaMundo m1) (huellaMundo m2)
        , "persistencia: huella cambia con una descripcion" ~: TestCase $ do
            let m1 = mundoDe textoBase
                m2 = mundoDe (cambiarLinea "DESC: La boveda." "DESC: Otra boveda." textoBase)
            assertBool "huellas distintas" (huellaMundo m1 /= huellaMundo m2)
        , "persistencia: guardar y cargar en archivo" ~: TestCase $ do
            directorio <- getTemporaryDirectory
            let ruta = directorio </> "aventura_partida_test.txt"
                m = mundoDe textoBase
                e1 = estadoTras [Tomar (identificador "linterna")] (estadoDe textoBase)
            guardado <- guardarPartida m ruta e1
            assertEqual "guardar" (Right ()) guardado
            cargado <- cargarPartida m ruta
            assertEqual "cargar" (Right e1) cargado
            removeFile ruta `catch` ignorarErrorIO
        , "persistencia: mensaje de mundo modificado" ~: TestCase $
            assertBool
                "mensaje"
                ("cambió" `isInfixOf` mensajeErrorPartida MundoModificado)
        ]

-- ---------------------------------------------------------------------------
-- Entrega
-- ---------------------------------------------------------------------------

testsEntrega :: Test
testsEntrega =
    TestList
        [ "entrega: el mundo es valido" ~: TestCase $ do
            texto <- readFile "mundos/entrega.txt"
            case leerMundo texto of
                Left errs -> assertFailure ("errores: " ++ show errs)
                Right _ -> pure ()
        , "mundo propio: el mundo es valido" ~: TestCase $ do
            texto <- readFile "mundos/mundo.txt"
            case leerMundo texto of
                Left errs -> assertFailure ("errores: " ++ show errs)
                Right m -> do
                    assertBool "al menos 8 salas" (Map.size (salas m) >= 8)
                    assertBool "al menos 6 objetos" (Map.size (objetos m) >= 6)
        , "entrega: el guion gana" ~: TestCase $ do
            textoMundo <- readFile "mundos/entrega.txt"
            textoGuion <- readFile "guiones/entrega.txt"
            case leerMundo textoMundo of
                Left errs -> assertFailure ("mundo invalido: " ++ show errs)
                Right m ->
                    case estadoInicial m of
                        Left err -> assertFailure ("inicio invalido: " ++ show err)
                        Right e0 -> do
                            let lineas = filter (not . null) (lines textoGuion)
                                comandos = mapMaybe leerComando lineas
                            assertEqual
                                "todas las lineas son comandos"
                                (length lineas)
                                (length comandos)
                            let eFinal = estadoTras comandos e0
                            assertBool "ha ganado" (haGanado eFinal)
        , "mundo propio: el guion gana" ~: TestCase $ do
            textoMundo <- readFile "mundos/mundo.txt"
            textoGuion <- readFile "guiones/mundo.txt"
            case leerMundo textoMundo of
                Left errs -> assertFailure ("mundo invalido: " ++ show errs)
                Right m ->
                    case estadoInicial m of
                        Left err -> assertFailure ("inicio invalido: " ++ show err)
                        Right e0 -> do
                            let lineas = filter (not . null) (lines textoGuion)
                                comandos = mapMaybe leerComando lineas
                            assertEqual
                                "todas las lineas son comandos"
                                (length lineas)
                                (length comandos)
                            let eFinal = estadoTras comandos e0
                            assertBool "ha ganado" (haGanado eFinal)
        , "invalidos propios: primer mundo reporta 3 errores" ~: TestCase $ do
            texto <- readFile "mundos/invalido_primero.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores"
                Left errs -> assertEqual "cantidad" 3 (length errs)
        , "invalidos propios: segundo mundo reporta 4 errores" ~: TestCase $ do
            texto <- readFile "mundos/invalido_segundo.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores"
                Left errs -> assertEqual "cantidad" 4 (length errs)
        , "invalidos propios: tercer mundo reporta 3 errores" ~: TestCase $ do
            texto <- readFile "mundos/invalido_tercero.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores"
                Left errs -> assertEqual "cantidad" 3 (length errs)
        , "invalidos propios: cuarto mundo reporta 2 errores" ~: TestCase $ do
            texto <- readFile "mundos/invalido_cuarto.txt"
            case leerMundo texto of
                Right _ -> assertFailure "se esperaban errores"
                Left errs -> do
                    assertEqual "cantidad" 2 (length errs)
                    assertEqual
                        "todos son sintacticos"
                        2
                        (length [n | ErrorSintaxis n _ <- errs])
        ]

-- ---------------------------------------------------------------------------
-- Ejecucion
-- ---------------------------------------------------------------------------

tests :: Test
tests =
    TestList
        [ "comandos" ~: testsComandos
        , "mundo" ~: testsMundo
        , "nucleo" ~: testsNucleo
        , "meta" ~: testsMeta
        , "persistencia" ~: testsPersistencia
        , "entrega" ~: testsEntrega
        ]

main :: IO ()
main = do
    resultados <- runTestTT tests
    if errors resultados + failures resultados == 0
        then exitSuccess
        else exitFailure
