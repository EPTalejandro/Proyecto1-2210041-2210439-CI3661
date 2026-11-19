## D1. Representación del mundo y los identificadores 

Redactado por: Alejandro Villamizar

**Contexto**:\
El motor del juego necesita almacenar las colecciones de salas y objetos extraídas del archivo de texto, y acceder a ellas constantemente durante la partida (por ejemplo, al ejecutar un comando de movimiento o examinar un objeto). El problema a resolver era cómo estructurar estas colecciones en el tipo Mundo para que las búsquedas fueran eficientes, y cómo modelar los identificadores para evitar mezclar accidentalmente descripciones de texto con referencias lógicas del juego.

**Opciones**:

    Usar listas tradicionales ([Sala] y [Objeto]) combinadas con un alias de tipo (type Identificador = String).

    Usar la estructura Map del paquete containers manteniendo los identificadores como String.

    Usar Map combinado con un envoltorio estricto (newtype Identificador = Identificador String).

**Decisión**:\
Elegimos la opción 3. Utilizamos diccionarios (Map.Map Identificador Sala) para almacenar las salas y los objetos. Optamos por esta estructura porque optimiza la velocidad de búsqueda y evita el diseño de funciones recursivas manuales para recorrer listas. Además, la función Map.lookup devuelve nativamente un tipo Maybe, lo cual nos proporciona un mecanismo seguro y natural para manejar los casos donde el usuario intenta interactuar con una sala o un objeto inexistente (cubriendo los errores de validación de referencias). Para los identificadores, descartamos el alias y creamos un tipo propio con newtype para dotar al dominio de mayor rigurosidad.

**Consecuencias**:\
Lo que ganamos (Invariante garantizado): El tipo newtype garantiza a nivel de compilador que es estructuralmente imposible pasar un texto libre (como un comando o una descripción) a una función que espera un identificador, previniendo errores lógicos durante la ejecución.

Lo que perdimos: Al usar newtype, perdimos la comodidad de tratar el texto directamente; ahora es necesario envolver y desenvolver manualmente los identificadores (usando pattern matching o funciones de extracción) al leer el archivo en nuestro módulo [Motor.Mundo] y al interactuar con el diccionario.

Lo que el tipo no garantiza: Nuestro Identificador garantiza que el dato tiene el formato correcto, pero el tipo por sí solo no garantiza la integridad semántica; es decir, no asegura que ese identificador exista realmente dentro de los diccionarios del Mundo. La garantía de existencia sigue dependiendo de la fase de validación lógica de nuestro motor.

## D2. Formas aceptadas de los comandos y de los identificadores

Redactado por: Alejandro Villamizar

**Contexto**:\
El PDF fija diez comandos mínimos y deja libres las variantes: artículos ("tomar la memoria"), abreviaturas ("n" por norte), mayúsculas y sinónimos adicionales. Había que decidir qué formas aceptar para que el reconocedor no fuera ambiguo, para que el jugador no tuviera que adivinar y para que las pruebas automáticas encontraran exactamente lo que esperan. El reconocedor de comandos vive en Motor.Comandos y es puro; el del mundo vive en Motor.Reconocedor y comparte con el primero la noción de identificador, pero no sus reglas de caja.

**Opciones**:
    
    Aceptar solo la forma literal del PDF y rechazar toda variante, incluidas mayúsculas.

    Aceptar variantes "humanas": artículos, abreviaturas, plurales y sinónimos inventados por nosotros.

    Aceptar los comandos de la tabla sin artículos ni abreviaturas, con verbos, direcciones e identificadores insensibles a mayúsculas, y conservar los dos sinónimos que el PDF lista como obligatorios: "coger" e "inv".

**Decisión**:\
Elegimos la opción 3. En Motor.Comandos, "leerComando" reconoce exactamente: mirar, ir <dirección>, tomar <objeto>, coger <objeto>, soltar <objeto>, examinar <objeto>, inventario, inv, guardar <archivo>, cargar <archivo>, ayuda y salir. No hay más sinónimos ni abreviaturas: "ver", "n" o "m" se rechazan. Los verbos y las direcciones se comparan sin distinguir mayúsculas de minúsculas mediante "cadenaInsensible". Los identificadores se reconocen con "pIdentificadorInsensible", que acepta las mismas letras que el formato del mundo pero en cualquier caja y los normaliza a minúsculas con "toLower"; así "Memoria_USB", "memoria_usb" y "MEMORIA_USB" designan el mismo objeto y también funcionan con acentos ("ÑANDÚ" se convierte en "ñandú"). El archivo del mundo, en cambio, sigue exigiendo identificadores en minúsculas porque "pIdentificador" no normaliza nada. No se aceptan artículos: "tomar la memoria" falla porque después de "tomar" el reconocedor lee el identificador "la" y sobra "memoria". Se exige al menos un espacio entre el verbo y su argumento, para que "tomarcarnet" no se interprete como "tomar carnet". Los espacios al inicio y al final de la línea se ignoran con "limpiarEspacios". "guardar" y "cargar" toman el resto de la línea como ruta, por lo que aceptan nombres con espacios; la ruta conserva mayúsculas y minúsculas porque es un nombre de archivo, no un identificador del juego. Una línea vacía y un comando desconocido producen mensajes distintos en "interpretarComando".

**Consecuencias**:\
Ganamos un conjunto de comandos pequeño y predecible, alineado con el PDF, sin ambigüedad entre verbos y objetos, y con una forma canónica de identificador en el estado del juego. Perdemos la comodidad de escribir "tomar la memoria usb": el jugador debe conocer o escribir el identificador exacto, aunque sea en mayúsculas. Mantener "coger" e "inv" es deliberado: el PDF los presenta como parte de los comandos mínimos, no como una libertad de diseño; quitarlos habría dejado incompleta la tabla. La decisión no valida que el objeto exista ni que esté en la sala: eso corresponde al núcleo, que responde con un mensaje cuando el identificador no está disponible. Si el enunciado hubiera permitido elegir, habríamos aceptado artículos con una lista cerrada ("el", "la", "los", "las") antes del identificador, pero preferimos no ampliar la gramática sin necesidad.

## D3. Uso de tipos de datos intermedios durante el reconocimiento y validación del mundo

Redactado por: Carlos Bisogno

**Contexto**:\
El tipo final `Mundo` definido en `Motor.Tipos` almacena las salas y los objetos en mapas (`Map.Map Identificador Sala`, `Map.Map Identificador Objeto`), y a su vez cada `Sala` almacena sus salidas en un mapa `Map.Map Direccion Salida`. Si durante el análisis sintáctico del archivo de texto intentáramos construir directamente estos tipos definitivos, la inserción en diccionarios (`Map.fromList` o inserciones sucesivas) sobrescribiría silenciosamente las entradas duplicadas (por ejemplo, dos declaraciones de salas con el mismo identificador o dos salidas hacia la misma dirección en una misma sala). Esto impediría detectar los errores obligatorios V2 (`IdentificadorDuplicado`) y V5 (`SalidasMismaDireccion`), o forzaría a intercalar comprobaciones ad-hoc durante el parseo, mezclando el análisis de sintaxis con la validación de integridad semántica. Además, el enunciado exige que si existen errores de sintaxis (V1 con número de línea), no debe intentarse validar la semántica, lo cual exige una separación estricta en etapas.

**Opciones**:

    1. Parsear directamente a los tipos de `Motor.Tipos` sobre la marcha, detectando duplicados durante la inserción en los mapas mediante funciones con acumulación de colisiones (como `Map.insertLookupWithKey` o acumuladores en mónadas de estado).

    2. Mantener las líneas del archivo únicamente como tuplas crudas de texto (`[(Int, String, String)]`) y ejecutar todas las validaciones semánticas (V2 a V10) inspeccionando cadenas de texto y listas antes de estructurar cualquier tipo de datos.

    3. Definir un AST intermedio de tipos planos (`RawCabecera`, `RawObjeto`, `RawSala`) en `Motor.Mundo`, preservando las ocurrencias en listas (`[Identificador]` para objetos de una sala, `[(Direccion, Salida)]` para salidas, y listas globales de salas y objetos). Una vez superada la fase de sintaxis (V1), las validaciones semánticas operan sobre estos tipos planos y, si no hay errores, una función pura construye el `Mundo` final empaquetando en `Map`.

**Decisión**:\
Elegimos la opción 3. En `Motor.Mundo`, definimos estructuras intermedias independientes de los mapas finales: `RawCabecera`, `RawObjeto` y `RawSala`. Durante el reconocimiento con los combinadores de `Motor.Reconocedor`, cada bloque sintácticamente válido se convierte a su tipo intermedio preservando el orden y la multiplicidad de las declaraciones en listas. Esto permite desacoplar completamente el pipeline en dos fases:
1. Fase sintáctica: procesa los bloques y líneas con `pClaveValor`, `pIdentificador`, `pSalida`, `pMeta` y `pBooleanoSiNo`, acumulando cualquier falla en `[ErrorMundo]` (como `ErrorSintaxis Int String`). Si esta lista no es vacía, se corta inmediatamente la ejecución y se reportan solo los errores V1.
2. Fase semántica: toma las estructuras intermedias limpias y ejecuta en paralelo las validaciones V2 a V10. Como las salidas y los objetos se mantuvieron en listas, la detección de V2 (duplicados de salas u objetos), V5 (duplicados de direcciones en `rawSalidasSala`) y V7 (objetos duplicados o en múltiples salas) se realiza de forma directa y pura usando funciones estándar sobre listas y conjuntos (`Data.Set`). Si no hay errores semánticos, la función `ensamblarMundo` convierte las listas a `Map.Map` y produce el `Mundo` final.

**Consecuencias**:\
Lo que ganamos: Separación limpia de responsabilidades (fase sintáctica vs. fase semántica). Garantizamos que no se pierdan datos por colisión de claves antes de tiempo, permitiendo reportar exhaustivamente todos los errores V2 a V10 sin omitir duplicados. El código de validación queda expresado como funciones puras sobre colecciones bien tipadas en lugar de sobre cadenas de texto crudo.
Lo que perdimos: Introducimos tipos de datos adicionales que existen únicamente dentro del módulo `Motor.Mundo` y requieren una función explícita de conversión (`ensamblarMundo`) para transformarlos en las estructuras de `Motor.Tipos`.
Qué haríamos distinto: Si la especificación no exigiera reportar errores sintácticos con número de línea y separar V1 de V2–V10 de forma tan estricta, habríamos usado un único tipo de datos con un funtor aplicativo de validación (`Validation`), pero para las restricciones y tipos cerrados del proyecto, el AST intermedio en dos etapas es la solución más robusta y legible.

## D4. Regla de entrada y comportamiento de las salas oscuras (variante 0)

Redactado por: Alejandro Villamizar

**Contexto**:\
La variante 0 agrega las claves `OSCURA: si` en las salas y `LUZ: si` en los objetos. El PDF deja abierto qué pasa cuando el jugador intenta entrar a una sala oscura y qué se puede hacer dentro de ella. Había que elegir una regla fácil de explicar, que no dejara al jugador atrapado y que se pudiera probar sin IO. El parser ya reconoce ambas claves y las guarda en `Sala.oscura` y `Objeto.ilumina`; la decisión pendiente era qué hacer con esa información en `Motor.Nucleo`. Además, como el jugador empieza sin objetos, una partida que comenzara en una sala oscura lo dejaría sin luz desde el primer turno.

**Opciones**:

    1. Permitir entrar siempre a la sala oscura, pero ocultar objetos y salidas y bloquear `tomar`/`examinar` mientras no haya luz (la mecánica clásica de exploración a ciegas).

    2. No permitir la entrada sin luz: mostrar un mensaje y dejar al jugador en la sala anterior; con un objeto que ilumine, entrar y comportarse normal. Añadir que la partida no pueda comenzar en una sala oscura.

    3. Permitir entrar y mostrar la descripción de la sala, pero ocultar objetos y salidas y bloquear las interacciones. La luz solo haría falta para interactuar, no para entrar.

**Decisión**:\
Elegimos la opción 2. En `Motor.Nucleo.ir`, después de comprobar que la salida existe y que el jugador lleva el objeto requerido, se consulta la sala de destino: si `oscura` es `True` y `llevaLuz e` es `False`, se devuelve únicamente el mensaje

    La habitación está oscura, será mejor buscar algo que dé luz.

y el estado no cambia; el jugador se queda donde estaba. Si `llevaLuz e` es `True`, el movimiento se realiza con normalidad y se describe la sala. Un objeto da luz si está en el inventario y su definición en `Mundo.objetos` tiene `ilumina = True`. La comprobación está centralizada en `llevaLuz`, que recorre `inventarioActual` y busca cada objeto con `objetoDe`; no se mira si el objeto está en la sala, porque la variante dice que la luz debe llevarla el jugador.

La regla se aplica solo al entrar. Si una partida cargada deja al jugador dentro de una sala oscura sin luz, `visible` devuelve `False`, `mirar` muestra el mensaje de oscuridad y no lista objetos ni salidas, y `tomar`/`examinar` de objetos de la sala fallan; sin embargo, `ir` sí lo deja salir, porque la comprobación de oscuridad se hace sobre la sala de destino y no sobre la actual. Así se evita un bloqueo permanente. `inventario`, `soltar`, `ayuda` y `examinar` de objetos que ya lleva el jugador siguen funcionando: la oscuridad oculta lo que hay en la sala, no lo que el jugador conoce de su inventario. `OSCURA` y `LUZ` solo aceptan `si`/`sí`/`no`; cualquier otro valor se reporta como error de sintaxis V1.

Para el comienzo, `estadoInicial` no devuelve un `Estado` directo sino `Either ErrorInicio Estado`. Si la sala `INICIO` no existe devuelve `SalaInicialInexistente`; si existe pero tiene `OSCURA: si` devuelve `SalaInicialOscura`, porque el inventario inicial está vacío y el jugador no tendría ninguna fuente de luz. `Main` traduce ese error a un mensaje y termina con código 1, en lugar de empezar una partida en la que el jugador no puede ver ni tomar nada. La comprobación se hace al crear la partida, no al cargar una partida guardada: una partida cargada dentro de una sala oscura es válida porque el jugador puede salir de ella.

**Consecuencias**:\
Ganamos una regla explícita y fácil de explicar: una sala oscura funciona como una puerta que necesita luz para abrirse, y el jugador recibe un mensaje claro en lugar de quedar dando vueltas sin información. También ganamos que la variante se pueda probar de forma pura: basta con construir un estado, ejecutar `Ir` y comprobar que `salaActual` no cambió, repetir con un objeto `LUZ` en el inventario, y comprobar que `estadoInicial` rechaza un mundo cuyo `INICIO` es oscuro. Perdemos la posibilidad de explorar a ciegas: la sala oscura deja de ser un espacio que se recorre sin ver y pasa a ser un destino bloqueado. Para que la variante importe en el mundo propio, la linterna debe estar disponible antes de la sala oscura y el objeto necesario para ganar debe estar dentro de ella. Queda una consecuencia aceptada: si el jugador suelta la única linterna dentro de una sala oscura, podrá salir pero no volver a recogerla; si se quiere evitar, más adelante se puede impedir soltar el último objeto que ilumina o permitir recogerlo a ciegas. Si el enunciado hubiera pedido exploración a ciegas, habríamos elegido la opción 1, pero habría hecho la variante más difícil de explicar y de probar.