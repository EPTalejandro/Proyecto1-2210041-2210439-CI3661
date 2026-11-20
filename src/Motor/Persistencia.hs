module Motor.Persistencia
    ( ErrorPartida (..)
    , mensajeErrorPartida
    , huellaMundo
    , serializarPartida
    , deserializarPartida
    , guardarPartida
    , cargarPartida
    ) where

import Control.Exception (evaluate)
import Data.Bits (xor)
import Data.Char (isSpace, ord)
import Data.List (foldl', intercalate)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import Numeric (showHex)
import System.IO (IOMode (ReadMode, WriteMode), hGetContents, hPutStr, withFile)
import System.IO.Error (ioeGetErrorString, tryIOError)

import Motor.Reconocedor (esCaracterId)
import Motor.Tipos

-- | Errores que puede producir guardar o cargar una partida.
data ErrorPartida
    = MundoModificado
        -- ^ La huella del mundo actual no coincide con la que se guardó.
    | PartidaCorrupta String
        -- ^ El archivo existe pero no tiene el formato esperado o sus
        -- referencias no cuadran con el mundo.
    | ErrorIO String
        -- ^ No se pudo leer o escribir el archivo.
    deriving (Eq, Show)

mensajeErrorPartida :: ErrorPartida -> String
mensajeErrorPartida err = case err of
    MundoModificado ->
        "El archivo del mundo cambió desde que se guardó la partida; no se puede cargar."
    PartidaCorrupta detalle ->
        "La partida guardada no es válida: " ++ detalle
    ErrorIO detalle ->
        "Error de entrada/salida: " ++ detalle

-- ---------------------------------------------------------------------------
-- Huella del mundo
-- ---------------------------------------------------------------------------

-- | Huella estable del mundo, usada para detectar que el archivo cambió
-- entre guardar y cargar una partida.
--
-- Se calcula sobre una representación canónica del mundo (no sobre el texto
-- del archivo), de modo que cambiar espacios, comentarios o el orden de las
-- líneas no invalida una partida, pero cambiar una sala, una salida, una
-- descripción, la meta, la oscuridad, la luz o la colocación inicial de los
-- objetos sí lo hace. La colocación dinámica de la partida (qué objetos
-- lleva el jugador y qué objetos se movieron) no forma parte de la huella:
-- se guarda aparte, porque es el estado de la partida y no del mundo.
huellaMundo :: Mundo -> String
huellaMundo = (`showHex` "") . fnv1a . canonicoMundo

fnv1a :: String -> Word64
fnv1a = foldl' paso 0xcbf29ce484222325
  where
    paso h c = (h `xor` fromIntegral (ord c)) * 0x100000001b3

canonicoMundo :: Mundo -> String
canonicoMundo m =
    intercalate "\n" $
        [ "MUNDO " ++ show (nombre m)
        , "INICIO " ++ texto (inicio m)
        , "META " ++ canonicoMeta (meta m)
        ]
            ++ [ "OBJETO "
                    ++ texto (idObjeto o)
                    ++ " "
                    ++ show (descObjeto o)
                    ++ " "
                    ++ canonicoBool (ilumina o)
               | (_, o) <- Map.toAscList (objetos m)
               ]
            ++ [ "SALA "
                    ++ texto (idSala s)
                    ++ " "
                    ++ show (descSala s)
                    ++ " "
                    ++ canonicoBool (oscura s)
                    ++ " SALIDAS "
                    ++ intercalate "," (map canonicoSalida (Map.toAscList (salidasSala s)))
                    ++ " OBJETOS "
                    ++ intercalate "," (map texto (objetosSala s))
               | (_, s) <- Map.toAscList (salas m)
               ]

canonicoMeta :: Meta -> String
canonicoMeta meta = case meta of
    LlegarA sala -> "llegar " ++ texto sala
    LlevarA obj sala -> "llevar " ++ texto obj ++ " " ++ texto sala

canonicoSalida :: (Direccion, Salida) -> String
canonicoSalida (d, salida) =
    nombreDireccion d
        ++ ">"
        ++ texto (destino salida)
        ++ ">"
        ++ maybe "-" texto (requisito salida)

canonicoBool :: Bool -> String
canonicoBool True = "si"
canonicoBool False = "no"

-- ---------------------------------------------------------------------------
-- Formato de la partida
-- ---------------------------------------------------------------------------

versionPartida :: String
versionPartida = "AVENTURA 1"

-- | Texto que se escribe en el archivo de una partida guardada. El primer
-- mundo que recibe es el mundo tal como se leyó del archivo (sin los
-- cambios de la partida); el segundo es el estado dinámico.
serializarPartida :: Mundo -> Estado -> String
serializarPartida m e =
    unlines $
        [ versionPartida
        , "MUNDO " ++ huellaMundo m
        , "SALA " ++ texto (salaActual e)
        , "INVENTARIO" ++ concatMap ((' ' :) . texto) (inventarioActual e)
        ]
            ++ [ "SALA-OBJETOS "
                    ++ texto (idSala s)
                    ++ concatMap ((' ' :) . texto) (objetosSala s)
               | (_, s) <- Map.toAscList (salas (mundoActual e))
               ]
            ++ ["FIN"]

-- | Reconstruye un estado a partir del texto de una partida, usando como
-- base el mundo recién leído del archivo. Falla con 'MundoModificado' si la
-- huella guardada no coincide con la del mundo actual.
deserializarPartida :: Mundo -> String -> Either ErrorPartida Estado
deserializarPartida m contenido = do
    cuerpo <- cuerpoPartida (lines contenido)
    comprobarClaves cuerpo
    huella <- campoUnico "MUNDO" cuerpo
    salaTexto <- campoUnico "SALA" cuerpo
    sala <- leerIdentificador salaTexto
    inventarioTexto <- campoUnico "INVENTARIO" cuerpo
    inventario <- mapM leerIdentificador (words inventarioTexto)
    colocaciones <- mapM leerColocacion (campos "SALA-OBJETOS" cuerpo)
    if huella /= huellaMundo m
        then Left MundoModificado
        else construirEstado m sala inventario colocaciones

cuerpoPartida :: [String] -> Either ErrorPartida [String]
cuerpoPartida lineas =
    case filter (not . null) (map recortar lineas) of
        [] -> corrupta "el archivo está vacío"
        (primera : resto)
            | primera /= versionPartida ->
                corrupta "el archivo no tiene el formato de una partida guardada"
            | null resto -> corrupta "falta la línea FIN"
            | last resto /= "FIN" -> corrupta "falta la línea FIN"
            | otherwise -> Right (init resto)

comprobarClaves :: [String] -> Either ErrorPartida ()
comprobarClaves cuerpo =
    case [linea | linea <- cuerpo, not (claveConocida linea)] of
        [] -> Right ()
        (linea : _) -> corrupta ("línea desconocida en la partida: " ++ linea)
  where
    claveConocida linea = maybe False (`elem` claves) (claveDe linea)
    claves = ["MUNDO", "SALA", "INVENTARIO", "SALA-OBJETOS"]

campoUnico :: String -> [String] -> Either ErrorPartida String
campoUnico clave lineas =
    case [valor | linea <- lineas, Just valor <- [valorDe clave linea]] of
        [valor] -> Right valor
        [] -> corrupta ("falta la línea '" ++ clave ++ "'")
        _ -> corrupta ("la línea '" ++ clave ++ "' aparece más de una vez")

campos :: String -> [String] -> [[String]]
campos clave lineas =
    [resto | linea <- lineas, c : resto <- [words linea], c == clave]

valorDe :: String -> String -> Maybe String
valorDe clave linea =
    case words linea of
        (c : resto) | c == clave -> Just (unwords resto)
        _ -> Nothing

claveDe :: String -> Maybe String
claveDe linea =
    case words linea of
        (c : _) -> Just c
        [] -> Nothing

leerColocacion :: [String] -> Either ErrorPartida (Identificador, [Identificador])
leerColocacion [] = corrupta "hay una línea SALA-OBJETOS sin sala"
leerColocacion (sala : objetos) = do
    idSala' <- leerIdentificador sala
    objetos' <- mapM leerIdentificador objetos
    pure (idSala', objetos')

leerIdentificador :: String -> Either ErrorPartida Identificador
leerIdentificador textoId
    | null textoId = corrupta "identificador vacío"
    | all esCaracterId textoId = Right (Identificador textoId)
    | otherwise = corrupta ("identificador inválido: " ++ textoId)

construirEstado
    :: Mundo
    -> Identificador
    -> [Identificador]
    -> [(Identificador, [Identificador])]
    -> Either ErrorPartida Estado
construirEstado m sala inventario colocaciones = do
    comprobar
        (Map.member sala (salas m))
        ("la sala actual '" ++ texto sala ++ "' no existe en el mundo")
    comprobar
        (null salasRepetidas)
        ("hay salas repetidas en la partida: " ++ listar salasRepetidas)
    comprobar
        (null objetosRepetidos)
        ("hay objetos repetidos en la partida: " ++ listar objetosRepetidos)
    mapM_
        (\s -> comprobar (Map.member s (salas m)) ("la sala '" ++ texto s ++ "' no existe en el mundo"))
        (map fst colocaciones)
    mapM_
        (\o -> comprobar (Map.member o (objetos m)) ("el objeto '" ++ texto o ++ "' no existe en el mundo"))
        (inventario ++ concatMap snd colocaciones)
    comprobar
        (Set.fromList (map fst colocaciones) == Set.fromList (Map.keys (salas m)))
        "faltan salas en la partida guardada"
    comprobar
        (null objetosPerdidos)
        ("faltan objetos por colocar: " ++ listar objetosPerdidos)
    pure
        Estado
            { mundoActual =
                m
                    { salas =
                        Map.mapWithKey
                            (\idS s -> s {objetosSala = Map.findWithDefault [] idS colocados})
                            (salas m)
                    }
            , salaActual = sala
            , inventarioActual = inventario
            }
  where
    colocados = Map.fromList colocaciones
    salasRepetidas = duplicados (map fst colocaciones)
    objetosRepetidos = duplicados (inventario ++ concatMap snd colocaciones)
    colocadosTodos = Set.fromList (inventario ++ concatMap snd colocaciones)
    objetosPerdidos =
        [o | o <- Map.keys (objetos m), o `Set.notMember` colocadosTodos]
    comprobar True _ = Right ()
    comprobar False mensaje = corrupta mensaje
    listar = intercalate ", " . map texto

duplicados :: Ord a => [a] -> [a]
duplicados xs =
    [x | (x, n) <- Map.toList (Map.fromListWith (+) [(x, 1 :: Int) | x <- xs]), n > 1]

corrupta :: String -> Either ErrorPartida a
corrupta = Left . PartidaCorrupta

recortar :: String -> String
recortar = quitarFinal . quitarInicio
  where
    quitarInicio = dropWhile isSpace
    quitarFinal = reverse . dropWhile isSpace . reverse

-- ---------------------------------------------------------------------------
-- Entrada/salida
-- ---------------------------------------------------------------------------

guardarPartida :: Mundo -> FilePath -> Estado -> IO (Either ErrorPartida ())
guardarPartida m ruta e = do
    resultado <-
        tryIOError $
            withFile ruta WriteMode (\h -> hPutStr h (serializarPartida m e))
    pure $ case resultado of
        Right () -> Right ()
        Left err ->
            Left (ErrorIO ("no se pudo escribir '" ++ ruta ++ "': " ++ ioeGetErrorString err))

cargarPartida :: Mundo -> FilePath -> IO (Either ErrorPartida Estado)
cargarPartida m ruta = do
    resultado <- tryIOError (withFile ruta ReadMode leerContenido)
    pure $ case resultado of
        Left err ->
            Left (ErrorIO ("no se pudo leer '" ++ ruta ++ "': " ++ ioeGetErrorString err))
        Right contenido -> deserializarPartida m contenido
  where
    leerContenido h = do
        contenido <- hGetContents h
        _ <- evaluate (length contenido)
        pure contenido

-- ---------------------------------------------------------------------------
-- Formato
-- ---------------------------------------------------------------------------

texto :: Identificador -> String
texto (Identificador s) = s

nombreDireccion :: Direccion -> String
nombreDireccion d = case d of
    Norte -> "norte"
    Sur -> "sur"
    Este -> "este"
    Oeste -> "oeste"
    Arriba -> "arriba"
    Abajo -> "abajo"
