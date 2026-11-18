module Motor.Mundo
    ( RawCabecera (..)
    , RawObjeto (..)
    , RawSala (..)
    , BloqueCrudo (..)
    , leerMundo
    ) where

import Data.List (nub, partition)
import qualified Data.Map as Map
import qualified Data.Set as Set

import Motor.Reconocedor
    ( dividirBloques
    , limpiarEspacios
    , pBooleanoSiNo
    , pClaveValor
    , pIdentificador
    , pMeta
    , pSalida
    , preprocesarLineas
    , reconocerCompleto
    )
import Motor.Tipos
    ( Direccion
    , Entidad (..)
    , ErrorMundo (..)
    , Identificador (..)
    , Meta (..)
    , Mundo (..)
    , Objeto (..)
    , Referencia (..)
    , Sala (..)
    , Salida (..)
    )


data RawCabecera = RawCabecera
    { rawNombre :: String
    , rawInicio :: Identificador
    , rawMeta   :: Meta
    }

data RawObjeto = RawObjeto
    { rawIdObjeto   :: Identificador
    , rawDescObjeto :: String
    , rawIlumina    :: Bool
    }

data RawSala = RawSala
    { rawIdSala      :: Identificador
    , rawDescSala    :: String
    , rawObjetosSala :: [Identificador]
    , rawSalidasSala :: [(Direccion, Salida)]
    , rawOscura      :: Bool
    }

data BloqueCrudo
    = BObjeto RawObjeto
    | BSala RawSala


leerMundo :: String -> Either [ErrorMundo] Mundo
leerMundo contenido =
    let lineas = preprocesarLineas contenido
        bloques = dividirBloques lineas
    in if null bloques
        then Left [ErrorSintaxis 1 "El archivo de mundo está vacío"]
        else
            let erroresFormato = concat
                    [errores
                    | linea <- lineas
                    , not (esSeparador (snd linea))
                    , let (errores, _) = parsearLinea linea]
                (bloqueHeader, bloquesRestantes) =
                    case bloques of
                        bloque : resto -> (bloque, resto)
                        [] -> ([], [])
                (erroresHeader, cabecera) = parsearCabecera bloqueHeader
                restoParseado = map parsearContenido bloquesRestantes
                erroresContenido = concatMap fst restoParseado
                contenidos = concatMap snd restoParseado
                (objetosCrudos, salasCrudas) = partitionBloques contenidos
                erroresV1 = erroresFormato ++ erroresHeader ++ erroresContenido
            in if not (null erroresV1)
                then Left erroresV1
                else
                    case cabecera of
                        Nothing -> Left erroresV1
                        Just rawCabecera ->
                            let erroresSemanticos =
                                    validarV2 salasCrudas objetosCrudos
                                    ++ validarV3 salasCrudas
                                    ++ validarV4 salasCrudas objetosCrudos
                                    ++ validarV5 salasCrudas
                                    ++ validarV6 salasCrudas objetosCrudos
                                    ++ validarV7 salasCrudas
                                    ++ validarV8 rawCabecera salasCrudas objetosCrudos
                                    ++ validarV9 rawCabecera salasCrudas
                                    ++ validarV10 rawCabecera salasCrudas objetosCrudos
                            in if not (null erroresSemanticos)
                                then Left erroresSemanticos
                                else Right (construirMundo rawCabecera salasCrudas objetosCrudos)


parsearLinea :: (Int, String) -> ([ErrorMundo], [(Int, (String, String))])
parsearLinea (num, texto) =
    case reconocerCompleto pClaveValor texto of
        Just par -> ([], [(num, par)])
        Nothing ->
            ([ErrorSintaxis num "Línea sin formato 'CLAVE: valor' o clave inválida"], [])


parsearCabecera
    :: [(Int, String)]
    -> ([ErrorMundo], Maybe RawCabecera)
parsearCabecera bloque =
    let pares =
            [(num, clave, valor)
            | (num, texto) <- bloque
            , Just (clave, valor) <- [reconocerCompleto pClaveValor texto]]
        erroresClave = concat
            [ [ErrorSintaxis num ("Clave desconocida en cabecera: " ++ clave)]
            | (num, clave, _) <- pares
            , clave `notElem` ["MUNDO", "INICIO", "META"]
            ]
        get clave = [(num, valor) | (num, c, valor) <- pares, c == clave]
        mundos = get "MUNDO"
        inicios = get "INICIO"
        metas = get "META"
        lineaCabecera = case bloque of
            ((num, _) : _) -> num
            [] -> 1
        erroresConteo =
               (if null mundos
                   then [ErrorSintaxis lineaCabecera "Falta campo obligatorio en cabecera: MUNDO"]
                   else [])
            ++ (if null inicios
                   then [ErrorSintaxis lineaCabecera "Falta campo obligatorio en cabecera: INICIO"]
                   else [])
            ++ (if null metas
                   then [ErrorSintaxis lineaCabecera "Falta campo obligatorio en cabecera: META"]
                   else [])
            ++ erroresRepetidosCampoCabecera "MUNDO" mundos
            ++ erroresRepetidosCampoCabecera "INICIO" inicios
            ++ erroresRepetidosCampoCabecera "META" metas
        inicioParseado = case inicios of
            ((num, valor) : _) ->
                case reconocerCompleto pIdentificador valor of
                    Just idInicio -> ([], Just idInicio)
                    Nothing ->
                        ([ErrorSintaxis num "Identificador de sala de inicio inválido"], Nothing)
            [] -> ([], Nothing)
        metaParseada = case metas of
            ((num, valor) : _) ->
                case reconocerCompleto pMeta valor of
                    Just meta -> ([], Just meta)
                    Nothing ->
                        ([ErrorSintaxis num "Sintaxis de META inválida (esperado 'llegar a <sala>' o 'llevar <objeto> a <sala>')"], Nothing)
            [] -> ([], Nothing)
        nombre = case mundos of
            ((_, valor) : _) -> limpiarEspacios valor
            [] -> ""
        cabecera = case (snd inicioParseado, snd metaParseada) of
            (Just inicio, Just meta) ->
                Just RawCabecera
                    { rawNombre = nombre
                    , rawInicio = inicio
                    , rawMeta = meta
                    }
            _ -> Nothing
    in (erroresClave ++ erroresConteo ++ fst inicioParseado ++ fst metaParseada, cabecera)


erroresRepetidosCampoCabecera
    :: String -> [(Int, String)] -> [ErrorMundo]
erroresRepetidosCampoCabecera campo entradas =
    case entradas of
        [] -> []
        (_ : extras) ->
            [ErrorSintaxis num ("Campo repetido en cabecera: " ++ campo)
            | (num, _) <- extras]


parsearContenido :: [(Int, String)] -> ([ErrorMundo], [BloqueCrudo])
parsearContenido [] = ([], [])
parsearContenido ((numPrimera, primera) : resto) =
    case reconocerCompleto pClaveValor primera of
        Nothing -> ([], [])
        Just (clave, valor) ->
            case clave of
                "OBJETO" ->
                    case reconocerCompleto pIdentificador valor of
                        Nothing ->
                            ([ErrorSintaxis numPrimera "Identificador de objeto inválido"], [])
                        Just idObjeto -> parsearObjeto numPrimera idObjeto resto
                "SALA" ->
                    case reconocerCompleto pIdentificador valor of
                        Nothing ->
                            ([ErrorSintaxis numPrimera "Identificador de sala inválido"], [])
                        Just idSala -> parsearSala numPrimera idSala resto
                _ ->
                    ([ErrorSintaxis numPrimera "El bloque debe iniciar con 'OBJETO:' o 'SALA:'"], [])


parsearObjeto :: Int -> Identificador -> [(Int, String)] -> ([ErrorMundo], [BloqueCrudo])
parsearObjeto numPrimera idObjeto resto =
    let pares =
            [(num, clave, valor)
            | (num, texto) <- resto
            , Just (clave, valor) <- [reconocerCompleto pClaveValor texto]]
        erroresClave = concat
            [ [ErrorSintaxis num ("Clave desconocida en objeto: " ++ clave)]
            | (num, clave, _) <- pares
            , clave `notElem` ["DESC", "LUZ"]
            ]
        get clave = [(num, valor) | (num, c, valor) <- pares, c == clave]
        descs = get "DESC"
        luces = get "LUZ"
        erroresDesc =
               (if null descs
                   then [ErrorSintaxis numPrimera "Falta campo obligatorio en objeto: DESC"]
                   else [])
            ++ erroresRepetidosCampo "DESC" descs
        erroresLuz = erroresRepetidosCampo "LUZ" luces
        erroresLuces =
            [ErrorSintaxis num "Sintaxis booleana inválida (esperado 'si' o 'no')"
            | (num, valor) <- luces
            , Nothing <- [reconocerCompleto pBooleanoSiNo valor]]
        il = case luces of
            ((_, valor) : _) ->
                case reconocerCompleto pBooleanoSiNo valor of
                    Just b -> b
                    Nothing -> False
            [] -> False
        descripcion = case descs of
            ((_, valor) : _) -> valor
            [] -> ""
        raw = RawObjeto
            { rawIdObjeto = idObjeto
            , rawDescObjeto = descripcion
            , rawIlumina = il
            }
        errores = erroresClave ++ erroresDesc ++ erroresLuz ++ erroresLuces
    in (errores,
        if null errores
            then [BObjeto raw]
            else [])


parsearSala :: Int -> Identificador -> [(Int, String)] -> ([ErrorMundo], [BloqueCrudo])
parsearSala numPrimera idSala resto =
    let pares =
            [(num, clave, valor)
            | (num, texto) <- resto
            , Just (clave, valor) <- [reconocerCompleto pClaveValor texto]]
        erroresClave = concat
            [ [ErrorSintaxis num ("Clave desconocida en sala: " ++ clave)]
            | (num, clave, _) <- pares
            , clave `notElem` ["DESC", "SALIDA", "OBJETO", "OSCURA"]
            ]
        get clave = [(num, valor) | (num, c, valor) <- pares, c == clave]
        descs = get "DESC"
        salidas = get "SALIDA"
        objetos = get "OBJETO"
        oscuras = get "OSCURA"
        erroresDesc =
               (if null descs
                   then [ErrorSintaxis numPrimera "Falta campo obligatorio en sala: DESC"]
                   else [])
            ++ erroresRepetidosCampo "DESC" descs
        erroresOscura = erroresRepetidosCampo "OSCURA" oscuras
        erroresOscuras =
            [ErrorSintaxis num "Sintaxis booleana inválida (esperado 'si' o 'no')"
            | (num, valor) <- oscuras
            , Nothing <- [reconocerCompleto pBooleanoSiNo valor]]
        erroresSalidas =
            [ErrorSintaxis num "Sintaxis de SALIDA inválida"
            | (num, valor) <- salidas
            , Nothing <- [reconocerCompleto pSalida valor]]
        erroresObjetos =
            [ErrorSintaxis num "Identificador de objeto inválido"
            | (num, valor) <- objetos
            , Nothing <- [reconocerCompleto pIdentificador valor]]
        salidasRaw =
            [salida
            | (_, valor) <- salidas
            , Just salida <- [reconocerCompleto pSalida valor]]
        objetosRaw =
            [obj
            | (_, valor) <- objetos
            , Just obj <- [reconocerCompleto pIdentificador valor]]
        oscura = case oscuras of
            ((_, valor) : _) ->
                case reconocerCompleto pBooleanoSiNo valor of
                    Just b -> b
                    Nothing -> False
            [] -> False
        descripcion = case descs of
            ((_, valor) : _) -> valor
            [] -> ""
        raw = RawSala
            { rawIdSala = idSala
            , rawDescSala = descripcion
            , rawObjetosSala = objetosRaw
            , rawSalidasSala = salidasRaw
            , rawOscura = oscura
            }
        errores =
            erroresClave ++ erroresDesc ++ erroresOscura ++ erroresOscuras
            ++ erroresSalidas ++ erroresObjetos
    in (errores,
        if null errores
            then [BSala raw]
            else [])


erroresRepetidosCampo :: String -> [(Int, String)] -> [ErrorMundo]
erroresRepetidosCampo campo entradas =
    case entradas of
        [] -> []
        (_ : extras) ->
            [ErrorSintaxis num ("Campo repetido en bloque: " ++ campo)
            | (num, _) <- extras]


esSeparador :: String -> Bool
esSeparador texto =
    not (null texto) && all (== '-') texto


partitionBloques :: [BloqueCrudo] -> ([RawObjeto], [RawSala])
partitionBloques bloques =
    let (objetos, salas) = partition esObjeto bloques
    in ([obj | BObjeto obj <- objetos], [sala | BSala sala <- salas])
  where
    esObjeto (BObjeto _) = True
    esObjeto (BSala _) = False


duplicados :: Eq a => [a] -> [a]
duplicados xs = nub [x | x <- nub xs, length (filter (== x) xs) > 1]


validarV2 :: [RawSala] -> [RawObjeto] -> [ErrorMundo]
validarV2 salas objetos =
       [IdentificadorDuplicado EntidadSala idSala
       | idSala <- duplicados [rawIdSala sala | sala <- salas]]
    ++ [IdentificadorDuplicado EntidadObjeto idObjeto
       | idObjeto <- duplicados [rawIdObjeto objeto | objeto <- objetos]]


validarV3 :: [RawSala] -> [ErrorMundo]
validarV3 salas =
    let validas = Set.fromList [rawIdSala sala | sala <- salas]
    in [SalidaASalaInexistente (rawIdSala sala) dir destinoId
       | sala <- salas
       , (dir, salida) <- rawSalidasSala sala
       , let destinoId = destino salida
       , destinoId `Set.notMember` validas]


validarV4 :: [RawSala] -> [RawObjeto] -> [ErrorMundo]
validarV4 salas objetos =
    let validos = Set.fromList [rawIdObjeto objeto | objeto <- objetos]
    in [SalidaRequiereObjetoInexistente (rawIdSala sala) dir obj
       | sala <- salas
       , (dir, salida) <- rawSalidasSala sala
       , Just obj <- [requisito salida]
       , obj `Set.notMember` validos]


validarV5 :: [RawSala] -> [ErrorMundo]
validarV5 salas =
    [SalidasMismaDireccion (rawIdSala sala) dir
    | sala <- salas
    , dir <- duplicados [dirSalida | (dirSalida, _) <- rawSalidasSala sala]]


validarV6 :: [RawSala] -> [RawObjeto] -> [ErrorMundo]
validarV6 salas objetos =
    let validos = Set.fromList [rawIdObjeto objeto | objeto <- objetos]
    in [SalaConObjetoNoDefinido (rawIdSala sala) obj
       | sala <- salas
       , obj <- rawObjetosSala sala
       , obj `Set.notMember` validos]


validarV7 :: [RawSala] -> [ErrorMundo]
validarV7 salas =
    let colocados =
            [obj
            | sala <- salas
            , obj <- rawObjetosSala sala]
    in [ObjetoMultiplesSalas obj | obj <- duplicados colocados]


validarV8 :: RawCabecera -> [RawSala] -> [RawObjeto] -> [ErrorMundo]
validarV8 cabecera salas objetos =
    let salasValidas = Set.fromList [rawIdSala sala | sala <- salas]
        objetosValidos = Set.fromList [rawIdObjeto objeto | objeto <- objetos]
        erroresInicio =
            [ReferenciaGlobalInexistente ReferenciaInicio (rawInicio cabecera)
            | rawInicio cabecera `Set.notMember` salasValidas]
        erroresMeta = case rawMeta cabecera of
            LlegarA sala ->
                [ReferenciaGlobalInexistente ReferenciaMeta sala
                | sala `Set.notMember` salasValidas]
            LlevarA obj sala ->
                   [ReferenciaGlobalInexistente ReferenciaMeta obj
                   | obj `Set.notMember` objetosValidos]
                ++ [ReferenciaGlobalInexistente ReferenciaMeta sala
                   | sala `Set.notMember` salasValidas]
    in erroresInicio ++ erroresMeta


validarV9 :: RawCabecera -> [RawSala] -> [ErrorMundo]
validarV9 cabecera salas =
    let salasValidas = Set.fromList [rawIdSala sala | sala <- salas]
    in if rawInicio cabecera `Set.member` salasValidas
        then
            let grafo = Map.fromList
                    [(rawIdSala sala,
                      [destino salida
                      | (_, salida) <- rawSalidasSala sala])
                    | sala <- salas]
                alcanzables = alcanzablesDesde grafo (rawInicio cabecera)
                idsUnicos = nub [rawIdSala sala | sala <- salas]
            in [SalaInalcanzable idSala
               | idSala <- idsUnicos
               , idSala `Set.notMember` alcanzables]
        else []


alcanzablesDesde
    :: Map.Map Identificador [Identificador]
    -> Identificador
    -> Set.Set Identificador
alcanzablesDesde grafo inicio = explorar Set.empty [inicio]
  where
    explorar visitados [] = visitados
    explorar visitados (actual : cola) =
        if actual `Set.member` visitados
            then explorar visitados cola
            else
                let visitados' = Set.insert actual visitados
                    vecinos = Map.findWithDefault [] actual grafo
                in explorar visitados' (cola ++ vecinos)


validarV10 :: RawCabecera -> [RawSala] -> [RawObjeto] -> [ErrorMundo]
validarV10 cabecera salas objetos =
    let objetosValidos = Set.fromList [rawIdObjeto objeto | objeto <- objetos]
        colocados = Set.fromList
            [obj
            | sala <- salas
            , obj <- rawObjetosSala sala]
        necesariosMeta = case rawMeta cabecera of
            LlevarA obj _ -> [obj]
            LlegarA _ -> []
        necesariosSalidas =
            [obj
            | sala <- salas
            , (_, salida) <- rawSalidasSala sala
            , Just obj <- [requisito salida]]
        necesarios = nub (necesariosMeta ++ necesariosSalidas)
    in [ObjetoNecesarioNoColocado obj
       | obj <- necesarios
       , obj `Set.member` objetosValidos
       , obj `Set.notMember` colocados]


construirMundo :: RawCabecera -> [RawSala] -> [RawObjeto] -> Mundo
construirMundo cabecera salas objetos =
    Mundo
        { nombre = rawNombre cabecera
        , inicio = rawInicio cabecera
        , salas = Map.fromList
            [(rawIdSala sala,
              Sala
                { idSala = rawIdSala sala
                , descSala = rawDescSala sala
                , objetosSala = rawObjetosSala sala
                , salidasSala = Map.fromList (rawSalidasSala sala)
                , oscura = rawOscura sala
                })
            | sala <- salas]
        , objetos = Map.fromList
            [(rawIdObjeto objeto,
              Objeto
                { idObjeto = rawIdObjeto objeto
                , descObjeto = rawDescObjeto objeto
                , ilumina = rawIlumina objeto
                })
            | objeto <- objetos]
        , meta = rawMeta cabecera
        }