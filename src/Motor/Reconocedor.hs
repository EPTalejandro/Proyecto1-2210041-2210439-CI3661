module Motor.Reconocedor
    ( Reconocedor (..)
    , reconocerCompleto
    , reconocerConError

    , caracter
    , satisfy
    , char
    , cadena
    , eof
    , (<|>)
    , elegir
    , muchos
    , muchos1
    , espacios
    , espacios1
    , restoLinea
    , opcion
    , entre
    , sepBy
    , sepBy1

    , esCaracterId
    , pIdentificador
    , pDireccion
    , pSalida
    , pMeta
    , pBooleanoSiNo
    , pClaveValor

    , limpiarEspacios
    , preprocesarLineas
    , dividirBloques
    ) where

import Control.Applicative (Alternative (..))
import Data.Char (isAsciiLower, isAsciiUpper, isDigit, isSpace)
import Data.List (stripPrefix)
import Motor.Tipos
    ( Direccion (..)
    , ErrorMundo (ErrorSintaxis)
    , Identificador (..)
    , Meta (..)
    , Salida (..)
    )

-- Combinador de reconocimiento envuelto sobre ReadS.
newtype Reconocedor a = Reconocedor {ejecutarReconocedor :: ReadS a}

instance Functor Reconocedor where
    fmap f (Reconocedor p) = Reconocedor $ \entrada ->
        [(f x, resto) | (x, resto) <- p entrada]

instance Applicative Reconocedor where
    pure x = Reconocedor $ \entrada -> [(x, entrada)]
    (Reconocedor pf) <*> (Reconocedor px) = Reconocedor $ \entrada ->
        [(f x, resto2) | (f, resto1) <- pf entrada, (x, resto2) <- px resto1]

-- | El reconocedor no es determinista: '(<|>)' devuelve todos los
-- resultados del primero seguidos de los del segundo. Eso permite
-- retroceder y probar alternativas sin perder resultados válidos.
instance Alternative Reconocedor where
    empty = Reconocedor (const [])
    Reconocedor p <|> Reconocedor q = Reconocedor $ \entrada -> p entrada ++ q entrada
    many = muchos
    some = muchos1

instance Monad Reconocedor where
    return = pure
    (Reconocedor p) >>= f = Reconocedor $ \entrada ->
        [ (y, resto2)
        | (x, resto1) <- p entrada
        , (y, resto2) <- ejecutarReconocedor (f x) resto1
        ]

-- | Ejecuta un reconocedor exigiendo que consuma toda la entrada
-- (ignorando espacios finales). Devuelve 'Nothing' si falla o sobra texto.
reconocerCompleto :: Reconocedor a -> String -> Maybe a
reconocerCompleto p entrada =
    case ejecutarReconocedor (p <* espacios <* eof) entrada of
        ((resultado, _) : _) -> Just resultado
        [] -> Nothing

-- | Variante de 'reconocerCompleto' que produce un 'ErrorSintaxis' con el
-- número de línea indicado si el reconocimiento falla.
reconocerConError :: Int -> String -> Reconocedor a -> String -> Either ErrorMundo a
reconocerConError numLinea msgError p entrada =
    case reconocerCompleto p entrada of
        Just val -> Right val
        Nothing -> Left (ErrorSintaxis numLinea msgError)

-- | Reconoce un carácter que cumpla el predicado dado.
caracter :: (Char -> Bool) -> Reconocedor Char
caracter predChar = Reconocedor $ \entrada ->
    case entrada of
        (c : cs) | predChar c -> [(c, cs)]
        _ -> []

-- | Alias de 'caracter' con el nombre habitual en los combinadores.
satisfy :: (Char -> Bool) -> Reconocedor Char
satisfy = caracter

-- | Reconoce un carácter exacto.
char :: Char -> Reconocedor Char
char c = caracter (== c)

-- | Reconoce una cadena exacta.
cadena :: String -> Reconocedor String
cadena prefijo = Reconocedor $ \entrada ->
    case stripPrefix prefijo entrada of
        Just resto -> [(prefijo, resto)]
        Nothing -> []

-- | Tiene éxito únicamente al llegar al final de la cadena de entrada.
eof :: Reconocedor ()
eof = Reconocedor $ \entrada ->
    case entrada of
        [] -> [((), [])]
        _ -> []

-- | Elige entre una lista de reconocedores usando '(<|>)'.
elegir :: [Reconocedor a] -> Reconocedor a
elegir = foldr (<|>) empty

-- | Cero o más repeticiones. Se detiene si el reconocedor no consume
-- entrada, para no entrar en un bucle infinito.
muchos :: Reconocedor a -> Reconocedor [a]
muchos p = Reconocedor resultados
  where
    resultados s =
        [ (x : xs, resto2)
        | (x, resto1) <- ejecutarReconocedor p s
        , resto1 /= s
        , (xs, resto2) <- resultados resto1
        ]
            ++ [([], s)]

-- | Una o más repeticiones de 'p'.
muchos1 :: Reconocedor a -> Reconocedor [a]
muchos1 p = (:) <$> p <*> muchos p

-- | Reconoce cero o más caracteres de espacio en blanco.
espacios :: Reconocedor String
espacios = muchos (caracter isSpace)

-- | Reconoce uno o más caracteres de espacio en blanco.
espacios1 :: Reconocedor String
espacios1 = muchos1 (caracter isSpace)

-- | Consume y devuelve todo el resto de la entrada.
restoLinea :: Reconocedor String
restoLinea = Reconocedor $ \entrada -> [(entrada, "")]

-- | Intenta aplicar el reconocedor; si falla, devuelve el valor por
-- defecto sin consumir entrada.
opcion :: a -> Reconocedor a -> Reconocedor a
opcion defecto p = p <|> pure defecto

-- | Reconoce un elemento delimitado por un prefijo y un sufijo.
entre :: Reconocedor open -> Reconocedor close -> Reconocedor a -> Reconocedor a
entre abrir cerrar p = abrir *> p <* cerrar

-- | Reconoce cero o más ocurrencias separadas por 'sep'.
sepBy :: Reconocedor a -> Reconocedor sep -> Reconocedor [a]
sepBy p sep = sepBy1 p sep <|> pure []

-- | Reconoce una o más ocurrencias separadas por 'sep'.
sepBy1 :: Reconocedor a -> Reconocedor sep -> Reconocedor [a]
sepBy1 p sep = (:) <$> p <*> muchos (sep *> p)

-- Caracteres válidos en identificadores de salas y objetos:
-- letras minúsculas (incluidas á, é, í, ó, ú, ñ, ü), dígitos y '_'.
esCaracterId :: Char -> Bool
esCaracterId c =
    isAsciiLower c
        || isDigit c
        || c == '_'
        || c `elem` "áéíóúñü"

-- | Reconoce un identificador válido sin espacios.
pIdentificador :: Reconocedor Identificador
pIdentificador = Identificador <$> muchos1 (caracter esCaracterId)

-- | Reconoce una dirección válida.
pDireccion :: Reconocedor Direccion
pDireccion =
    elegir
        [ Norte <$ cadena "norte"
        , Sur <$ cadena "sur"
        , Este <$ cadena "este"
        , Oeste <$ cadena "oeste"
        , Arriba <$ cadena "arriba"
        , Abajo <$ cadena "abajo"
        ]

-- | Reconoce el valor de una línea SALIDA:
-- @<dirección> -> <sala>@ o
-- @<dirección> -> <sala> requiere <objeto>@.
pSalida :: Reconocedor (Direccion, Salida)
pSalida = do
    _ <- espacios
    dir <- pDireccion
    _ <- espacios
    _ <- cadena "->"
    _ <- espacios
    dest <- pIdentificador
    req <- opcion Nothing $ do
        _ <- espacios1
        _ <- cadena "requiere"
        _ <- espacios1
        Just <$> pIdentificador
    pure (dir, Salida {destino = dest, requisito = req})

-- | Reconoce el valor de la clave META:
-- @llegar a <sala>@ o @llevar <objeto> a <sala>@.
pMeta :: Reconocedor Meta
pMeta = pLlegar <|> pLlevar
  where
    pLlegar = do
        _ <- espacios
        _ <- cadena "llegar"
        _ <- espacios1
        _ <- cadena "a"
        _ <- espacios1
        LlegarA <$> pIdentificador

    pLlevar = do
        _ <- espacios
        _ <- cadena "llevar"
        _ <- espacios1
        obj <- pIdentificador
        _ <- espacios1
        _ <- cadena "a"
        _ <- espacios1
        LlevarA obj <$> pIdentificador

-- | Reconoce valores booleanos de la Variante 0 (Oscuridad):
-- @OSCURA: si@ y @LUZ: si@.
pBooleanoSiNo :: Reconocedor Bool
pBooleanoSiNo = do
    _ <- espacios
    elegir
        [ True <$ cadena "si"
        , True <$ cadena "sí"
        , False <$ cadena "no"
        ]

-- | Reconoce una línea con formato @CLAVE: valor@. La clave empieza en
-- mayúscula y sigue con mayúsculas, dígitos o '_'. El valor no puede
-- quedar vacío tras recortar espacios.
pClaveValor :: Reconocedor (String, String)
pClaveValor = do
    _ <- espacios
    clave <- (:) <$> caracter isAsciiUpper <*> muchos (caracter esCaracterClave)
    _ <- char ':'
    _ <- espacios
    resto <- restoLinea
    let valor = limpiarEspacios resto
    if null valor
        then empty
        else pure (clave, valor)
  where
    esCaracterClave c = isAsciiUpper c || isDigit c || c == '_'

-- | Elimina espacios en blanco al inicio y al final de una cadena.
limpiarEspacios :: String -> String
limpiarEspacios = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- | Numera las líneas del archivo desde 1, elimina los espacios al inicio
-- y al final, y descarta líneas vacías o comentarios.
preprocesarLineas :: String -> [(Int, String)]
preprocesarLineas contenido =
    [ (num, limpia)
    | (num, raw) <- zip [1 ..] (lines contenido)
    , let limpia = limpiarEspacios raw
    , not (null limpia)
    , take 1 limpia /= "#"
    ]

-- | Divide las líneas en bloques separados por líneas que contienen
-- únicamente guiones, conservando el número de línea original.
dividirBloques :: [(Int, String)] -> [[(Int, String)]]
dividirBloques [] = []
dividirBloques ls =
    let (bloque, resto) = break (esSeparador . snd) ls
        restoSinSep = dropWhile (esSeparador . snd) resto
     in if null bloque
            then dividirBloques restoSinSep
            else bloque : dividirBloques restoSinSep
  where
    esSeparador s = not (null s) && all (== '-') s
