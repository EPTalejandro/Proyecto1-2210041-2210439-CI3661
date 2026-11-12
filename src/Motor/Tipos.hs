import qualified Data.Map as Map

newtype Identificador = Identificador String
    deriving(Eq,Show)
data Direccion = Norte | Sur | Este | Oeste | Arriba | Abajo
    deriving(Eq,Show)

data Objeto = Objeto {
    idObjeto :: Identificador,
    descObjeto :: String,
    ilumina :: Bool
}

data Sala = Sala {
    idSala :: Identificador,
    descSala :: String,
    objetosSala :: Map.Map Identificador Objeto,
    salidasSala :: Map.Map Direccion Identificador, -- sujetador, probablemente lo cambie
    oscuridad :: Bool
}

data Mundo = Mundo {
    nombre :: String,
    inicio :: Identificador, -- indetificador de sala
    salas :: Map.Map Identificador Identificador,
    objetos :: Map.Map Identificador Objeto,
    meta :: Meta
}

type Meta =  Identificador

data Comando = Mirar | Inventario | Ir Direccion | Tomar Identificador | Guardar String | Soltar Identificador |
                    Cargar String | Ayuda | Salir

data Salida = Salida {
    destino:: Identificador,
    requesito :: Maybe Identificador
}

data ErrorMundo 
    -- V1: Errores de sintaxis (clave, línea, campos, salidas, direcciones, etc.)
    -- Requiere el número de línea y un mensaje describiendo el problema de sintaxis.
    = ErrorSintaxis Int String
    
    -- V2: Identificador duplicado en salas u objetos.
    -- Guarda el identificador que está repetido.
    | IdentificadorDuplicado Identificador
    
    -- V3: Salida hacia una sala inexistente.
    -- Guarda: ID de la sala de origen, Dirección, ID de la sala destino que no existe.
    | SalidaASalaInexistente Identificador Direccion Identificador
    
    -- V4: Salida bloqueada por un objeto que no existe.
    -- Guarda: ID de la sala de origen, Dirección, ID del objeto que no existe.
    | SalidaRequiereObjetoInexistente Identificador Direccion Identificador
    
    -- V5: Choque de salidas en la misma sala (ej. dos salidas al Norte).
    -- Guarda: ID de la sala, y la Dirección que está repetida.
    | SalidasMismaDireccion Identificador Direccion
    
    -- V6: Una sala dice tener un objeto que no está definido en el mundo.
    -- Guarda: ID de la sala, ID del objeto no definido.
    | SalaConObjetoNoDefinido Identificador Identificador
    
    -- V7: Un objeto está clonado en múltiples lugares.
    -- Guarda: ID del objeto que se encontró en múltiples salas.
    | ObjetoMultiplesSalas Identificador
    
    -- V8: INICIO o META referencian algo que no existe.
    -- Un simple String como parámetro para aclarar si falló "Inicio" o "Meta", y el ID que falló.
    | ReferenciaGlobalInexistente String Identificador
    
    -- V9: Una sala es inalcanzable (grafo desconectado).
    -- Guarda el ID de la sala a la que es imposible llegar.
    | SalaInalcanzable Identificador
    
    -- V10: Un objeto es necesario (meta/salida) pero no fue instanciado en ninguna sala.
    -- Guarda el ID del objeto que falta en el mapa.
    | ObjetoNecesarioNoColocado Identificador
    deriving (Eq, Show)