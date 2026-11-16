module Motor.Reconocedor
    ( limpiarEspacios
    , preprocesarLineas
    , dividirBloques
    ) where

import Data.Char (isSpace)
import Motor.Tipos
    ( Comando (..)
    , Direccion (..)
    , ErrorMundo (ErrorSintaxis)
    , Identificador (..)
    , Salida (..)
    )

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