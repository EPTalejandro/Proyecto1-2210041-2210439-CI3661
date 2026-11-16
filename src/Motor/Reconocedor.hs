module Motor.Reconocedor where

import Data.Char (isAlphaNum, isSpace)
import Motor.Tipos


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