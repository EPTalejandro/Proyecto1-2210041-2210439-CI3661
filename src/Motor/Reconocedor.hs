module Motor.Reconocedor
    ( Reconocedor (..)
    , reconocerCompleto
    , reconocerConError

    , caracter
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
    , CondicionMeta (..)
    , pMeta
    , pBooleanoSiNo
    , pClaveValor
    , pComando

    , limpiarEspacios
    , preprocesarLineas
    , dividirBloques
    ) where

import Data.Char (isAsciiLower, isDigit, isAlphaNum, isSpace, isUpper, toLower)
import Motor.Tipos
    ( Comando (..)
    , Direccion (..)
    , ErrorMundo (ErrorSintaxis)
    , Identificador (..)
    , Salida (..)
    )

-- Combinador de reconocimiento envuelto sobre ReadS
newtype Reconocedor a = Reconocedor {ejecutarReconocedor :: ReadS a}

instance Functor Reconocedor where
    fmap f (Reconocedor p) = Reconocedor $ \entrada ->
        [(f x, resto) | (x, resto) <- p entrada]

instance Applicative Reconocedor where
    pure x = Reconocedor $ \entrada -> [(x, entrada)]
    (Reconocedor pf) <*> (Reconocedor px) = Reconocedor $ \entrada ->
        [(f x, resto2) | (f, resto1) <- pf entrada, (x, resto2) <- px resto1]

instance Monad Reconocedor where
    return = pure
    (Reconocedor p) >>= f = Reconocedor $ \entrada ->
        [ (y, resto2)
        | (x, resto1) <- p entrada
        , (y, resto2) <- ejecutarReconocedor (f x) resto1
        ]

-- Ejecuta un reconocedor exigiendo que consuma toda la entrada
-- (ignorando espacios finales). Devuelve Nothing si falla o sobra texto.
reconocerCompleto :: Reconocedor a -> String -> Maybe a
reconocerCompleto p entrada =
    case ejecutarReconocedor (p <* espacios <* eof) entrada of
        ((resultado, _) : _) -> Just resultado
        [] -> Nothing

-- Variante de reconocerCompleto que produce un ErrorSintaxis con el
-- número de línea indicado si el reconocimiento falla.
reconocerConError :: Int -> String -> Reconocedor a -> String -> Either ErrorMundo a
reconocerConError numLinea msgError p entrada =
    case reconocerCompleto p entrada of
        Just val -> Right val
        Nothing -> Left (ErrorSintaxis numLinea msgError)




-- Reconoce un carácter que cumpla el predicado dado.
caracter :: (Char -> Bool) -> Reconocedor Char
caracter predChar = Reconocedor $ \entrada ->
    case entrada of
        (c : cs) | predChar c -> [(c, cs)]
        _ -> []

-- Reconoce un carácter exacto.
char :: Char -> Reconocedor Char
char c = caracter (== c)

-- Reconoce una cadena exacta.
cadena :: String -> Reconocedor String
cadena prefijo = Reconocedor $ \entrada ->
    case stripPrefix prefijo entrada of
        Just resto -> [(prefijo, resto)]
        Nothing -> []

-- Tiene éxito únicamente al llegar al final de la cadena de entrada.
eof :: Reconocedor ()
eof = Reconocedor $ \entrada ->
    case entrada of
        [] -> [((), [])]
        _ -> []

-- Elige entre una lista de reconocedores usando <|>.
elegir :: [Reconocedor a] -> Reconocedor a
elegir = foldr (<|>) fallar
  where
    fallar = Reconocedor (const [])

muchos :: Reconocedor a -> Reconocedor [a]
muchos p = uno <|> ninguno
  where
    ninguno = pure []
    uno = do
        x <- p
        xs <- muchos p
        pure (x : xs)

-- Una o más repeticiones de p.
muchos1 :: Reconocedor a -> Reconocedor [a]
muchos1 p = (:) <$> p <*> muchos p

-- Reconoce cero o más caracteres de espacio en blanco.
espacios :: Reconocedor String
espacios = many (satisfy isSpace)

-- Reconoce uno o más caracteres de espacio en blanco.
espacios1 :: Reconocedor String
espacios1 = some (satisfy isSpace)

-- Consume y devuelve todo el resto de la entrada.
restoLinea :: Reconocedor String
restoLinea = Reconocedor $ \entrada -> [(entrada, "")]

-- Intenta aplicar el reconocedor; si falla, devuelve el valor por defecto sin consumir entrada.
opcion :: a -> Reconocedor a -> Reconocedor a
opcion defecto p = p <|> pure defecto

-- Reconoce un elemento delimitado por un prefijo y un sufijo.
entre :: Reconocedor open -> Reconocedor close -> Reconocedor a -> Reconocedor a
entre abrir cerrar p = abrir *> p <* cerrar

-- Reconoce cero o más ocurrencias separadas por sep.
sepBy :: Reconocedor a -> Reconocedor sep -> Reconocedor [a]
sepBy p sep = sepBy1 p sep <|> pure []

-- Reconoce una o más ocurrencias separadas por sep.
sepBy1 :: Reconocedor a -> Reconocedor sep -> Reconocedor [a]
sepBy1 p sep = (:) <$> p <*> many (sep *> p)



-- Caracteres válidos en identificadores de salas y objetos:
-- letras minúsculas (incluidas á, é, í, ó, ú, ñ, ü), dígitos y guion bajo '_'.
esCaracterId :: Char -> Bool
esCaracterId c =
    isAsciiLower c
        || isDigit c
        || c == '_'
        || c `elem` "áéíóúñü"

-- Reconoce un Identificador válido sin espacios.
pIdentificador :: Reconocedor Identificador
pIdentificador = Identificador <$> muchos1 (caracter esCaracterId)

-- Reconoce una Direccion válida.
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

-- Reconoce el valor de una línea SALIDA:
-- <dirección> -> <sala> o 
-- <dirección> -> <sala> requiere <objeto>.
pSalida :: Reconocedor (Direccion, Salida)
pSalida = do
    _ <- espacios
    dir <- pDireccion
    _ <- espacios1
    _ <- cadena "->"
    _ <- espacios1
    dest <- pIdentificador
    req <- opcion Nothing $ do
        _ <- espacios1
        _ <- cadena "requiere"
        _ <- espacios1
        Just <$> pIdentificador
    pure (dir, Salida {destino = dest, requesito = req})

-- Representación intermedia de la condición de victoria en META:
data CondicionMeta
    = LlegarA Identificador
    | LlevarA Identificador Identificador
    deriving (Eq, Show)

-- Reconoce el valor de la clave META:
-- llegar a <sala> o llevar <objeto> a <sala>.
pMeta :: Reconocedor CondicionMeta
pMeta :: Reconocedor CondicionMeta
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

-- Reconoce valores booleanos de la Variante 0 (Oscuridad): OSCURA: si / LUZ: si.
pBooleanoSiNo :: Reconocedor Bool
pBooleanoSiNo = do
    _ <- espacios
    elegir
        [ True <$ cadena "si"
        , True <$ cadena "sí"
        , False <$ cadena "no"
        ]

-- Reconoce una línea con formato CLAVE: valor, donde CLAVE está en
-- mayúsculas y valor no es vacío tras recortar espacios.
pClaveValor :: Reconocedor (String, String)
pClaveValor = do
    _ <- espacios
    clave <- muchos1 (caracter isUpper)
    _ <- char ':'
    _ <- espacios
    rawVal <- restoLinea
    let val = limpiarEspacios rawVal
    if null val
        then Reconocedor (const [])
        else pure (clave, val)

-- Reconoce un Comando ingresado por el jugador.
pComando :: Reconocedor Comando
pComando = Reconocedor $ \entrada ->
    let normalizada = limpiarEspacios entrada
        (verbo, resto) = break isSpace normalizada
        entradaNorm = map toLower verbo ++ resto
     in ejecutarReconocedor pComandoNorm entradaNorm
  where
    pComandoNorm :: Reconocedor Comando
    pComandoNorm =
        elegir
            [ pIr
            , Mirar <$ cadena "mirar"
            , pTomar
            , pSoltar
            , Inventario <$ (cadena "inventario" <|> cadena "inv")
            , pGuardar
            , pCargar
            , Ayuda <$ cadena "ayuda"
            , Salir <$ cadena "salir"
            ]

    pIr = do
        _ <- cadena "ir"
        _ <- espacios1
        Ir <$> pDireccion

    pTomar = do
        _ <- cadena "tomar" <|> cadena "coger"
        _ <- espacios1
        Tomar <$> pIdentificador

    pSoltar = do
        _ <- cadena "soltar"
        _ <- espacios1
        Soltar <$> pIdentificador

    pGuardar = do
        _ <- cadena "guardar"
        _ <- espacios1
        ruta <- limpiarEspacios <$> restoLinea
        if null ruta then Reconocedor (const []) else pure (Guardar ruta)

    pCargar = do
        _ <- cadena "cargar"
        _ <- espacios1
        ruta <- limpiarEspacios <$> restoLinea
        if null ruta then Reconocedor (const []) else pure (Cargar ruta)




-- Elimina espacios en blanco al inicio y al final de una cadena.
limpiarEspacios :: String -> String
limpiarEspacios = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- Numera las líneas del archivo desde 1, elimina los espacios al inicio y al final,
-- y descarta líneas vacías o comentarios.
preprocesarLineas :: String -> [(Int, String)]
preprocesarLineas contenido =
    [ (num, limpia)
    | (num, raw) <- zip [1 ..] (lines contenido)
    , let limpia = limpiarEspacios raw
    , not (null limpia)
    , not ("#" `esPrefijoDe` limpia)
    ]
  where
    esPrefijoDe [] _ = True
    esPrefijoDe _ [] = False
    esPrefijoDe (x : xs) (y : ys) = x == y && esPrefijoDe xs ys

-- Divide las líneas en bloques separados por líneas que contienen únicamente "-" 
-- y conservando el número de línea original de cada entrada.
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

cumple :: (Char -> Bool) -> ReadS Char
cumple condicion (c:cs)
    | condicion c = [(c, cs)]
cumple _ _        = []

cadena :: String -> ReadS String
cadena [] resto = [("", resto)]
cadena (p:ps) (c:cs)
    | p == c = [ (p : cola, sobrante) | (cola, sobrante) <- cadena ps cs ]
cadena _ _ = []

muchos :: ReadS a -> ReadS [a]
muchos r texto =
    case r texto of
        []           -> [([], texto)]
        [(x, resto)] -> [ (x : xs, sobrante) | (xs, sobrante) <- muchos r resto ]

-- Combinador especializado para tragar espacios en blanco opcionales:
espacios :: ReadS String
espacios = muchos (cumple isSpace)

unoOMas :: ReadS a -> ReadS [a]
unoOMas r texto =
    [ (x : xs, sobrante)
    | (x, resto)     <- r texto
    , (xs, sobrante) <- muchos r resto
    ]

leerIdentificador :: ReadS Identificador
leerIdentificador texto =
    [ (Identificador chars, resto)
    | (chars, resto) <- unoOMas (cumple esValido) texto
    ]
  where
    esValido c = isAlphaNum c || c == '_'

leerDireccion :: ReadS Direccion
leerDireccion texto =
       leer "norte" Norte texto
    ++ leer "sur" Sur texto
    ++ leer "este" Este texto
    ++ leer "oeste" Oeste texto
    ++ leer "arriba" Arriba texto
    ++ leer "abajo" Abajo texto
  where
    leer palabra direccion entrada =
        [(direccion, resto) | (_, resto) <- cadena palabra entrada]