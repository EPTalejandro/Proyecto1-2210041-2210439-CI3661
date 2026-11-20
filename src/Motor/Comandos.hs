module Motor.Comandos
    ( leerComando
    , interpretarComando
    ) where

import Control.Applicative (empty)
import Data.Char (toLower)
import Motor.Reconocedor
    ( Reconocedor (..)
    , caracter
    , elegir
    , esCaracterId
    , espacios1
    , limpiarEspacios
    , muchos1
    , reconocerCompleto
    , restoLinea
    )
import Motor.Tipos
    ( Comando (..)
    , Direccion (..)
    , Identificador (..)
    )

-- | Reconoce una línea del jugador y devuelve el comando correspondiente.
-- Es pura: no toca la entrada ni la salida.
--
-- Se ignoran los espacios al inicio y al final. Los verbos, las
-- direcciones y los identificadores se aceptan sin distinguir mayúsculas
-- de minúsculas; los identificadores se normalizan a minúsculas, que es la
-- forma canónica del archivo del mundo. No se aceptan artículos ni
-- abreviaturas: el objeto se nombra por su identificador exacto. Una
-- dirección sola, como @norte@, es un atajo de @ir norte@.
leerComando :: String -> Maybe Comando
leerComando = reconocerCompleto pComando . limpiarEspacios

-- | Variante de 'leerComando' que explica al jugador qué pasó. La usa
-- 'Main' para distinguir una línea vacía de un comando desconocido.
interpretarComando :: String -> Either String Comando
interpretarComando entrada =
    case leerComando entrada of
        Just cmd -> Right cmd
        Nothing
            | null (limpiarEspacios entrada) ->
                Left "Por favor, escribe un comando. Escribe 'ayuda' para ver las opciones."
            | otherwise ->
                Left "Comando no reconocido. Escribe 'ayuda' para ver las opciones."

pComando :: Reconocedor Comando
pComando =
    elegir
        [ comandoSinArgumentos "mirar" Mirar
        , comandoSinArgumentos "inventario" Inventario
        , comandoSinArgumentos "inv" Inventario
        , comandoSinArgumentos "ayuda" Ayuda
        , comandoSinArgumentos "salir" Salir
        , comandoIr
        , comandoConId (elegir [cadenaInsensible "tomar", cadenaInsensible "coger"]) Tomar
        , comandoConId (cadenaInsensible "soltar") Soltar
        , comandoConId (cadenaInsensible "examinar") Examinar
        , comandoConRuta (cadenaInsensible "guardar") Guardar
        , comandoConRuta (cadenaInsensible "cargar") Cargar
        -- Atajo: una dirección sola equivale a "ir <dirección>".
        , Ir <$> direccionInsensible
        ]

-- | Comandos de una sola palabra, sin argumentos.
comandoSinArgumentos :: String -> Comando -> Reconocedor Comando
comandoSinArgumentos verbo comando = comando <$ cadenaInsensible verbo

-- | Comando @ir \<direccion\>@. La dirección también es insensible a
-- mayúsculas.
comandoIr :: Reconocedor Comando
comandoIr = do
    _ <- cadenaInsensible "ir"
    _ <- espacios1
    Ir <$> direccionInsensible

-- | Comandos @tomar \<objeto\>@, @soltar \<objeto\>@ y @examinar \<objeto\>@.
-- Exigimos al menos un espacio entre el verbo y el identificador para que
-- @tomarcarnet@ no se acepte como @tomar carnet@.
comandoConId :: Reconocedor String -> (Identificador -> Comando) -> Reconocedor Comando
comandoConId verbo constructor = do
    _ <- verbo
    _ <- espacios1
    constructor <$> pIdentificadorInsensible

-- | Comandos @guardar \<archivo\>@ y @cargar \<archivo\>@. La ruta es todo
-- el resto de la línea, así que puede contener espacios.
comandoConRuta :: Reconocedor String -> (FilePath -> Comando) -> Reconocedor Comando
comandoConRuta verbo constructor = do
    _ <- verbo
    _ <- espacios1
    ruta <- limpiarEspacios <$> restoLinea
    if null ruta
        then empty
        else pure (constructor ruta)

-- | Identificador escrito por el jugador: las mismas letras que admite el
-- formato del mundo, pero sin distinguir mayúsculas de minúsculas. Se
-- normaliza a minúsculas para que @Memoria_USB@ y @memoria_usb@ sean el
-- mismo objeto. No se aceptan artículos ni espacios dentro del nombre.
pIdentificadorInsensible :: Reconocedor Identificador
pIdentificadorInsensible =
    Identificador . map toLower
        <$> muchos1 (caracter (esCaracterId . toLower))

-- | Dirección reconocida sin distinguir mayúsculas de minúsculas.
direccionInsensible :: Reconocedor Direccion
direccionInsensible =
    elegir
        [ Norte <$ cadenaInsensible "norte"
        , Sur <$ cadenaInsensible "sur"
        , Este <$ cadenaInsensible "este"
        , Oeste <$ cadenaInsensible "oeste"
        , Arriba <$ cadenaInsensible "arriba"
        , Abajo <$ cadenaInsensible "abajo"
        ]

-- | Reconoce una palabra ignorando mayúsculas y minúsculas. No consume
-- nada más que la palabra: el resto de la línea queda intacto.
cadenaInsensible :: String -> Reconocedor String
cadenaInsensible palabra = Reconocedor $ \entrada ->
    let (prefijo, resto) = splitAt (length palabra) entrada
     in [ (prefijo, resto)
        | map toLower prefijo == map toLower palabra
        ]
