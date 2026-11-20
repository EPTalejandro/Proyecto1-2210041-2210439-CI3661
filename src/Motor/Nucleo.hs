module Motor.Nucleo
    ( estadoInicial
    , mensajeErrorInicio
    , ejecutar
    , haGanado
    ) where

import Data.List (delete, intercalate)
import qualified Data.Map as Map
import Motor.Tipos

-- | Estado inicial de una partida: el jugador empieza en la sala INICIO,
-- sin objetos en el inventario y con el mundo recién cargado.
--
-- La partida no puede comenzar en una sala oscura: el jugador arranca sin
-- objetos y, por lo tanto, sin ninguna fuente de luz, así que quedaría
-- atrapado sin poder ver ni tomar nada. En ese caso se devuelve
-- 'SalaInicialOscura' y 'Main' termina con error en lugar de empezar a jugar.
estadoInicial :: Mundo -> Either ErrorInicio Estado
estadoInicial m =
    case Map.lookup (inicio m) (salas m) of
        Nothing -> Left (SalaInicialInexistente (inicio m))
        Just s
            | oscura s -> Left (SalaInicialOscura (inicio m))
            | otherwise ->
                Right
                    Estado
                        { mundoActual = m
                        , salaActual = inicio m
                        , inventarioActual = []
                        }

-- | Mensaje para el jugador cuando 'estadoInicial' rechaza el comienzo.
mensajeErrorInicio :: ErrorInicio -> String
mensajeErrorInicio err = case err of
    SalaInicialInexistente sala ->
        "No se puede iniciar la partida: la sala inicial \""
            ++ texto sala
            ++ "\" no existe."
    SalaInicialOscura sala ->
        "No se puede iniciar la partida: la sala inicial \""
            ++ texto sala
            ++ "\" está oscura y el jugador no lleva ninguna fuente de luz."

-- | Ejecuta un comando de juego de forma pura. Devuelve los mensajes para
-- el jugador y el estado nuevo.
--
-- Guardar, cargar y salir necesitan IO, así que Main los intercepta antes
-- de llamar a esta función. Aun así tienen que aparecer aquí para que el
-- case sea exhaustivo.
ejecutar :: Comando -> Estado -> ([String], Estado)
ejecutar cmd e = case cmd of
    Mirar       -> (mirar e, e)
    Inventario  -> (listarInventario e, e)
    Ir d        -> ir d e
    Tomar o     -> tomar o e
    Soltar o    -> soltar o e
    Examinar o  -> examinar o e
    Ayuda       -> (textoAyuda, e)
    Guardar _   -> (["El guardado se gestiona desde Main."], e)
    Cargar _    -> (["La carga se gestiona desde Main."], e)
    Salir       -> (["Hasta luego."], e)

-- | ¿Se cumplió la meta del mundo?
haGanado :: Estado -> Bool
haGanado e =
    case meta (mundoActual e) of
        LlegarA sala -> salaActual e == sala
        LlevarA obj sala ->
            salaActual e == sala && obj `elem` inventarioActual e

-- ---------------------------------------------------------------------------
-- Consultas sobre el estado
-- ---------------------------------------------------------------------------

salaDe :: Estado -> Maybe Sala
salaDe e = Map.lookup (salaActual e) (salas (mundoActual e))

objetoDe :: Identificador -> Estado -> Maybe Objeto
objetoDe i e = Map.lookup i (objetos (mundoActual e))

lleva :: Identificador -> Estado -> Bool
lleva i e = i `elem` inventarioActual e

-- | ¿El jugador lleva algún objeto que dé luz?
llevaLuz :: Estado -> Bool
llevaLuz e =
    any ilumina
        [objeto | i <- inventarioActual e, Just objeto <- [objetoDe i e]]

-- | Una sala oscura solo se puede ver si el jugador lleva luz.
visible :: Estado -> Sala -> Bool
visible e s = not (oscura s) || llevaLuz e

mensajeOscuro :: String
mensajeOscuro =
    "La habitación está oscura, será mejor buscar algo que dé luz."

-- ---------------------------------------------------------------------------
-- Modificaciones del mundo
-- ---------------------------------------------------------------------------

conSala :: Identificador -> (Sala -> Sala) -> Estado -> Estado
conSala i f e =
    e {mundoActual = m {salas = Map.adjust f i (salas m)}}
  where
    m = mundoActual e

quitarDeSala :: Identificador -> Identificador -> Estado -> Estado
quitarDeSala sala obj =
    conSala sala (\s -> s {objetosSala = filter (/= obj) (objetosSala s)})

ponerEnSala :: Identificador -> Identificador -> Estado -> Estado
ponerEnSala sala obj =
    conSala sala (\s -> s {objetosSala = objetosSala s ++ [obj]})

-- ---------------------------------------------------------------------------
-- Comandos
-- ---------------------------------------------------------------------------

mirar :: Estado -> [String]
mirar e = case salaDe e of
    Nothing -> ["No estás en una sala válida."]
    Just s
        | not (visible e s) -> [mensajeOscuro]
        | otherwise ->
            descSala s
                : describirObjetos s
                ++ describirSalidas s

describirObjetos :: Sala -> [String]
describirObjetos s =
    case objetosSala s of
        [] -> ["No hay objetos."]
        objetos -> ["Objetos: " ++ intercalate ", " (map texto objetos)]

describirSalidas :: Sala -> [String]
describirSalidas s =
    case salidasOrdenadas s of
        [] -> ["No hay salidas."]
        salidas ->
            [ "Salidas: "
                ++ intercalate ", "
                    [ nombreDir d
                        ++ " -> "
                        ++ texto (destino salida)
                        ++ marcaRequisito (requisito salida)
                    | (d, salida) <- salidas
                    ]
            ]
  where
    marcaRequisito Nothing = ""
    marcaRequisito (Just obj) = " (requiere " ++ texto obj ++ ")"

salidasOrdenadas :: Sala -> [(Direccion, Salida)]
salidasOrdenadas s =
    [ (d, salida)
    | d <- [minBound .. maxBound]
    , Just salida <- [Map.lookup d (salidasSala s)]
    ]

ir :: Direccion -> Estado -> ([String], Estado)
ir d e = case salaDe e of
    Nothing -> (["No estás en una sala válida."], e)
    Just s ->
        case Map.lookup d (salidasSala s) of
            Nothing -> (["No hay salida al " ++ nombreDir d ++ "."], e)
            Just salida
                | Just obj <- requisito salida
                , not (lleva obj e) ->
                    ( [ "La salida al " ++ nombreDir d
                          ++ " está bloqueada: necesitas " ++ texto obj ++ "."
                      ]
                    , e
                    )
                | otherwise ->
                    case Map.lookup (destino salida) (salas (mundoActual e)) of
                        Nothing ->
                            (["La sala de destino no existe."], e)
                        Just destinoSala
                            | oscura destinoSala && not (llevaLuz e) ->
                                ([mensajeOscuro], e)
                            | otherwise ->
                                let e' = e {salaActual = destino salida}
                                 in ( ("Vas al " ++ nombreDir d ++ ".")
                                        : mirar e'
                                    , e'
                                    )

tomar :: Identificador -> Estado -> ([String], Estado)
tomar obj e = case salaDe e of
    Nothing -> (["No estás en una sala válida."], e)
    Just s
        | not (visible e s) -> ([mensajeOscuro], e)
        | obj `notElem` objetosSala s ->
            (["No hay " ++ texto obj ++ " aquí."], e)
        | otherwise ->
            let e1 = quitarDeSala (salaActual e) obj e
                e2 = e1 {inventarioActual = obj : inventarioActual e1}
             in (["Tomas " ++ texto obj ++ "."], e2)

soltar :: Identificador -> Estado -> ([String], Estado)
soltar obj e
    | not (lleva obj e) = (["No llevas " ++ texto obj ++ "."], e)
    | otherwise =
        let e1 = e {inventarioActual = delete obj (inventarioActual e)}
            e2 = ponerEnSala (salaActual e) obj e1
         in (["Sueltas " ++ texto obj ++ "."], e2)

examinar :: Identificador -> Estado -> ([String], Estado)
examinar obj e =
    case objetoDe obj e of
        Nothing -> (["No existe el objeto " ++ texto obj ++ "."], e)
        Just objeto
            | lleva obj e -> ([descObjeto objeto], e)
            | otherwise ->
                case salaDe e of
                    Nothing -> (["No estás en una sala válida."], e)
                    Just s
                        | obj `elem` objetosSala s ->
                            if visible e s
                                then ([descObjeto objeto], e)
                                else ([mensajeOscuro], e)
                        | otherwise ->
                            (["No ves " ++ texto obj ++ " aquí."], e)

listarInventario :: Estado -> [String]
listarInventario e =
    case inventarioActual e of
        [] -> ["No llevas nada."]
        objetos -> ["Llevas: " ++ intercalate ", " (map texto objetos)]

textoAyuda :: [String]
textoAyuda =
    [ "Comandos disponibles:"
    , "  mirar"
    , "  ir <dirección>    (también puedes escribir solo la dirección)"
    , "  tomar <objeto>    (sinónimo: coger)"
    , "  soltar <objeto>"
    , "  examinar <objeto>"
    , "  inventario        (sinónimo: inv)"
    , "  guardar <archivo>"
    , "  cargar <archivo>"
    , "  ayuda"
    , "  salir"
    ]

-- ---------------------------------------------------------------------------
-- Formato
-- ---------------------------------------------------------------------------

texto :: Identificador -> String
texto (Identificador s) = s

nombreDir :: Direccion -> String
nombreDir d = case d of
    Norte -> "norte"
    Sur -> "sur"
    Este -> "este"
    Oeste -> "oeste"
    Arriba -> "arriba"
    Abajo -> "abajo"
