import qualified Data.Map as Map

newtype Identificador = Identificador String

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
    salida :: String, -- sujetador, probablemente lo cambie
    oscuridad :: Bool
}

data Mundo = Mundo {
    nombre :: String,
    inicio :: Identificador, -- indetificador de sala
    salas :: Map.Map Identificador Sala,
    objetos :: Map.Map Identificador Objeto,
    meta :: Meta
}

data Meta 
