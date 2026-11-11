D1. Representación del mundo y los identificadores (Redactado por: Alejandro Villamizar)

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