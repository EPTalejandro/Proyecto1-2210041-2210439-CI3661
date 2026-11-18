## D1. Representación del mundo y los identificadores 

Redactado por: Alejandro Villamizar

Contexto:
El motor del juego necesita almacenar las colecciones de salas y objetos extraídas del archivo de texto, y acceder a ellas constantemente durante la partida (por ejemplo, al ejecutar un comando de movimiento o examinar un objeto). El problema a resolver era cómo estructurar estas colecciones en el tipo Mundo para que las búsquedas fueran eficientes, y cómo modelar los identificadores para evitar mezclar accidentalmente descripciones de texto con referencias lógicas del juego.

Opciones:

    Usar listas tradicionales ([Sala] y [Objeto]) combinadas con un alias de tipo (type Identificador = String).

    Usar la estructura Map del paquete containers manteniendo los identificadores como String.

    Usar Map combinado con un envoltorio estricto (newtype Identificador = Identificador String).

Decisión:
Elegimos la opción 3. Utilizamos diccionarios (Map.Map Identificador Sala) para almacenar las salas y los objetos. Optamos por esta estructura porque optimiza la velocidad de búsqueda y evita el diseño de funciones recursivas manuales para recorrer listas. Además, la función Map.lookup devuelve nativamente un tipo Maybe, lo cual nos proporciona un mecanismo seguro y natural para manejar los casos donde el usuario intenta interactuar con una sala o un objeto inexistente (cubriendo los errores de validación de referencias). Para los identificadores, descartamos el alias y creamos un tipo propio con newtype para dotar al dominio de mayor rigurosidad.

Consecuencias:

    Lo que ganamos (Invariante garantizado): El tipo newtype garantiza a nivel de compilador que es estructuralmente imposible pasar un texto libre (como un comando o una descripción) a una función que espera un identificador, previniendo errores lógicos durante la ejecución.

    Lo que perdimos: Al usar newtype, perdimos la comodidad de tratar el texto directamente; ahora es necesario envolver y desenvolver manualmente los identificadores (usando pattern matching o funciones de extracción) al leer el archivo en nuestro módulo [Motor.Mundo] y al interactuar con el diccionario.

    Lo que el tipo no garantiza: Nuestro Identificador garantiza que el dato tiene el formato correcto, pero el tipo por sí solo no garantiza la integridad semántica; es decir, no asegura que ese identificador exista realmente dentro de los diccionarios del Mundo. La garantía de existencia sigue dependiendo de la fase de validación lógica de nuestro motor.

## D2. Formas aceptadas de los comandos y de los identificadores

Redactado por: Alejandro Villamizar

Contexto:
El PDF fija diez comandos mínimos y deja libres las variantes: artículos ("tomar la memoria"), abreviaturas ("n" por norte), mayúsculas y sinónimos adicionales. Había que decidir qué formas aceptar para que el reconocedor no fuera ambiguo, para que el jugador no tuviera que adivinar y para que las pruebas automáticas encontraran exactamente lo que esperan. El reconocedor de comandos vive en Motor.Comandos y es puro; el del mundo vive en Motor.Reconocedor y comparte con el primero la noción de identificador, pero no sus reglas de caja.

Opciones:
    
    Aceptar solo la forma literal del PDF y rechazar toda variante, incluidas mayúsculas.

    Aceptar variantes "humanas": artículos, abreviaturas, plurales y sinónimos inventados por nosotros.

    Aceptar los comandos de la tabla sin artículos ni abreviaturas, con verbos, direcciones e identificadores insensibles a mayúsculas, y conservar los dos sinónimos que el PDF lista como obligatorios: "coger" e "inv".

Decisión:
Elegimos la opción 3. En Motor.Comandos, "leerComando" reconoce exactamente: mirar, ir <dirección>, tomar <objeto>, coger <objeto>, soltar <objeto>, examinar <objeto>, inventario, inv, guardar <archivo>, cargar <archivo>, ayuda y salir. No hay más sinónimos ni abreviaturas: "ver", "n" o "m" se rechazan. Los verbos y las direcciones se comparan sin distinguir mayúsculas de minúsculas mediante "cadenaInsensible". Los identificadores se reconocen con "pIdentificadorInsensible", que acepta las mismas letras que el formato del mundo pero en cualquier caja y los normaliza a minúsculas con "toLower"; así "Memoria_USB", "memoria_usb" y "MEMORIA_USB" designan el mismo objeto y también funcionan con acentos ("ÑANDÚ" se convierte en "ñandú"). El archivo del mundo, en cambio, sigue exigiendo identificadores en minúsculas porque "pIdentificador" no normaliza nada. No se aceptan artículos: "tomar la memoria" falla porque después de "tomar" el reconocedor lee el identificador "la" y sobra "memoria". Se exige al menos un espacio entre el verbo y su argumento, para que "tomarcarnet" no se interprete como "tomar carnet". Los espacios al inicio y al final de la línea se ignoran con "limpiarEspacios". "guardar" y "cargar" toman el resto de la línea como ruta, por lo que aceptan nombres con espacios; la ruta conserva mayúsculas y minúsculas porque es un nombre de archivo, no un identificador del juego. Una línea vacía y un comando desconocido producen mensajes distintos en "interpretarComando".

Consecuencias:
Ganamos un conjunto de comandos pequeño y predecible, alineado con el PDF, sin ambigüedad entre verbos y objetos, y con una forma canónica de identificador en el estado del juego. Perdemos la comodidad de escribir "tomar la memoria usb": el jugador debe conocer o escribir el identificador exacto, aunque sea en mayúsculas. Mantener "coger" e "inv" es deliberado: el PDF los presenta como parte de los comandos mínimos, no como una libertad de diseño; quitarlos habría dejado incompleta la tabla. La decisión no valida que el objeto exista ni que esté en la sala: eso corresponde al núcleo, que responde con un mensaje cuando el identificador no está disponible. Si el enunciado hubiera permitido elegir, habríamos aceptado artículos con una lista cerrada ("el", "la", "los", "las") antes del identificador, pero preferimos no ampliar la gramática sin necesidad.