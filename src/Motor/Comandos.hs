module Motor.Comandos where

import Data.Char (isSpace, toLower)
import Motor.Reconocedor
    ( cadena
    , cumple
    , leerDireccion
    , leerIdentificador
    , limpiarEspacios
    , unoOMas
    )
import Motor.Tipos
    ( Comando (..)
    , Direccion
    , Identificador
    )

-- | Función principal exportada: recibe la entrada cruda del jugador desde Main
-- y devuelve un Comando tipado o un mensaje de error claro.
interpretarComando :: String -> Either String Comando
interpretarComando entrada =
    let limpia = limpiarEspacios entrada
     in if null limpia
            then Left "Por favor, escribe un comando. Escribe 'ayuda' para ver las opciones."
            else case leerComando limpia of
                [(cmd, "")] -> Right cmd
                _           -> Left "Comando no reconocido. Escribe 'ayuda' para ver las opciones."

-- | Combinador maestro que prueba todas las gramáticas de comandos posibles.
leerComando :: ReadS Comando
leerComando texto =
       leerSinArgs "mirar" Mirar texto
    ++ leerSinArgs "inventario" Inventario texto
    ++ leerSinArgs "ayuda" Ayuda texto
    ++ leerSinArgs "salir" Salir texto
    ++ leerIr texto
    ++ leerConId "tomar" Tomar texto
    ++ leerConId "soltar" Soltar texto
    ++ leerConRuta "guardar" Guardar texto
    ++ leerConRuta "cargar" Cargar texto

-- | Reconoce comandos de una sola palabra sin argumentos (insensible a mayúsculas).
leerSinArgs :: String -> Comando -> ReadS Comando
leerSinArgs verbo constructor texto =
    [ (constructor, resto)
    | (_, resto) <- cadenaInsensible verbo texto
    ]

-- | Reconoce el comando de movimiento: "ir <direccion>" (ej. "ir norte").
leerIr :: ReadS Comando
leerIr texto =
    [ (Ir dir, resto)
    | (_, r1)      <- cadenaInsensible "ir" texto
    , (_, r2)      <- espaciosObligatorios r1
    , (dir, resto) <- leerDireccionInsensible r2
    ]

-- | Reconoce comandos que reciben un Identificador (ej. "tomar llave_maestra").
-- Preserva las mayúsculas/minúsculas originales del identificador.
leerConId :: String -> (Identificador -> Comando) -> ReadS Comando
leerConId verbo constructor texto =
    [ (constructor ident, resto)
    | (_, r1)        <- cadenaInsensible verbo texto
    , (_, r2)        <- espaciosObligatorios r1
    , (ident, resto) <- leerIdentificador r2
    ]

-- | Reconoce comandos que reciben una ruta de archivo sin espacios (ej. "guardar partida1.txt").
leerConRuta :: String -> (String -> Comando) -> ReadS Comando
leerConRuta verbo constructor texto =
    [ (constructor ruta, resto)
    | (_, r1)       <- cadenaInsensible verbo texto
    , (_, r2)       <- espaciosObligatorios r1
    , (ruta, resto) <- unoOMas (cumple (not . isSpace)) r2
    ]

-- | Consume al menos un espacio en blanco para evitar pegar verbo y argumento (ej. "irnorte").
espaciosObligatorios :: ReadS String
espaciosObligatorios = unoOMas (cumple isSpace)

-- | Variante de 'cadena' que ignora diferencias entre mayúsculas y minúsculas
-- (útil para que "IR", "Ir" e "ir" funcionen por igual).
cadenaInsensible :: String -> ReadS String
cadenaInsensible [] resto = [("", resto)]
cadenaInsensible (p : ps) (c : cs)
    | toLower p == toLower c =
        [ (c : cola, sobrante) | (cola, sobrante) <- cadenaInsensible ps cs ]
cadenaInsensible _ _ = []

-- | Adapta 'leerDireccion' normalizando la palabra a minúsculas antes de evaluarla.
leerDireccionInsensible :: ReadS Direccion
leerDireccionInsensible texto =
    let (palabra, resto) = span (not . isSpace) texto
     in [ (dir, resto)
        | (dir, "") <- leerDireccion (map toLower palabra)
        ]