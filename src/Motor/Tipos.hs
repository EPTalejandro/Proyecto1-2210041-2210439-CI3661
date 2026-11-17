module Motor.Tipos where

import qualified Data.Map as Map

-- | Identificador de una sala o de un objeto. Salas y objetos tienen
-- espacios de nombres separados: un mismo identificador puede existir
-- como sala y como objeto sin conflicto.
newtype Identificador = Identificador String
    deriving (Eq, Ord, Show)

data Direccion = Norte | Sur | Este | Oeste | Arriba | Abajo
    deriving (Eq, Ord, Show, Enum, Bounded)

data Objeto = Objeto
    { idObjeto   :: Identificador
    , descObjeto :: String
    , ilumina    :: Bool  -- ^ Variante 0 (Oscuridad): ¿el objeto da luz?
    }
    deriving (Eq, Show)

-- | Una salida de una sala. El requisito es el objeto que hay que llevar
-- en el inventario para poder cruzar la salida.
data Salida = Salida
    { destino   :: Identificador
    , requisito :: Maybe Identificador
    }
    deriving (Eq, Show)

data Sala = Sala
    { idSala      :: Identificador
    , descSala    :: String
    , objetosSala :: [Identificador]
        -- ^ Solo guardamos identificadores: la definición de cada objeto
        -- vive una única vez en 'objetos' del 'Mundo'. Así no hay copias
        -- que puedan contradecirse y V6/V7 se comprueban sobre referencias.
    , salidasSala :: Map.Map Direccion Salida
    , oscura      :: Bool  -- ^ Variante 0 (Oscuridad).
    }
    deriving (Eq, Show)

data Meta
    = LlegarA Identificador
    | LlevarA Identificador Identificador
        -- ^ 'LlevarA objeto sala': estar en la sala con el objeto en el
        -- inventario.
    deriving (Eq, Show)

data Mundo = Mundo
    { nombre  :: String
    , inicio  :: Identificador
    , salas   :: Map.Map Identificador Sala
    , objetos :: Map.Map Identificador Objeto
    , meta    :: Meta
    }
    deriving (Eq, Show)

data Comando
    = Mirar
    | Inventario
    | Ir Direccion
    | Tomar Identificador
    | Soltar Identificador
    | Examinar Identificador
    | Guardar FilePath
    | Cargar FilePath
    | Ayuda
    | Salir
    deriving (Eq, Show)

-- | Estado dinámico de la partida. 'ejecutar' tiene la firma
-- @Comando -> Estado -> ([String], Estado)@, así que el mundo (del que
-- dependen las descripciones, las salidas y los objetos) tiene que estar
-- dentro del estado. Los objetos que el jugador suelta se quitan de
-- 'inventarioActual' y se añaden a la sala correspondiente de 'mundoActual'.
data Estado = Estado
    { mundoActual      :: Mundo
    , salaActual       :: Identificador
    , inventarioActual :: [Identificador]
    }
    deriving (Eq, Show)

-- | Ayuda a distinguir los dos espacios de nombres al reportar un
-- identificador duplicado.
data Entidad = EntidadSala | EntidadObjeto
    deriving (Eq, Show)

-- | De dónde sale una referencia global que no existe (V8).
data Referencia = ReferenciaInicio | ReferenciaMeta
    deriving (Eq, Show)

data ErrorMundo
    -- V1: errores de sintaxis, con el número de línea.
    = ErrorSintaxis Int String

    -- V2: dos salas o dos objetos con el mismo identificador.
    | IdentificadorDuplicado Entidad Identificador

    -- V3: salida hacia una sala inexistente.
    | SalidaASalaInexistente Identificador Direccion Identificador

    -- V4: salida que requiere un objeto inexistente.
    | SalidaRequiereObjetoInexistente Identificador Direccion Identificador

    -- V5: dos salidas en la misma dirección dentro de una sala.
    | SalidasMismaDireccion Identificador Direccion

    -- V6: sala que contiene un objeto no definido.
    | SalaConObjetoNoDefinido Identificador Identificador

    -- V7: objeto colocado en más de una sala (o dos veces en la misma).
    | ObjetoMultiplesSalas Identificador

    -- V8: INICIO o META apuntan a una sala u objeto inexistente.
    | ReferenciaGlobalInexistente Referencia Identificador

    -- V9: sala inalcanzable desde INICIO.
    | SalaInalcanzable Identificador

    -- V10: objeto necesario (meta o requisito) que no está en ninguna sala.
    | ObjetoNecesarioNoColocado Identificador
    deriving (Eq, Show)
