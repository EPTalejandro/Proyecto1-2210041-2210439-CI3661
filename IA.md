# Uso de inteligencia artificial

## Gemini web
Gemini web se utilizó para ayudar a diseñar la estructura básica del proyecto,
crear el paquete de Cabal y entender qué es Cabal y cómo funciona.

## OpenCode con DeepSeek
Se utilizó OpenCode con el modelo DeepSeek (V4.1 Flash Free) para comentar
`Motor.Reconocedor`, que es el archivo con más lógica del proyecto, y para
eliminar código viejo y redundante que había quedado de versiones anteriores.
También se usó para redactar borradores de `DECISIONES.md` y de este mismo
archivo `IA.md`: uno de los integrantes tomaba la decisión, se la describía al
agente, este redactaba una propuesta, el integrante repasaba la respuesta y
finalmente la aprobaba o la corregía.

También se utilizó para la suite de pruebas: se creó el esqueleto de
`test/Spec.hs` y se usó como apoyo para redactar los casos de `leerMundo`,
`ejecutar` y `leerComando`.

### Ejemplo de una sugerencia que corregimos
En el borrador de D2 se planteó eliminar todos los sinónimos de los comandos,
incluidos `coger` e `inv`. Al revisar el PDF notamos que la tabla de comandos
mínimos los incluye explícitamente, así que rechazamos esa parte de la
sugerencia y mantuvimos ambos sinónimos. La decisión final solo rechaza
artículos, abreviaturas y sinónimos adicionales, y tanto el código de
`Motor.Comandos` como el texto de D2 se corrigieron para reflejarlo.

Todo el código y las decisiones fueron revisados y aprobados por los
integrantes; la IA se usó como apoyo, no como autora. Esta misma declaración
se redactó con el agente a partir de la información que le dieron los
integrantes y después fue revisada por ellos.
