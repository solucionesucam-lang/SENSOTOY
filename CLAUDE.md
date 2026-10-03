Proyecto SENSOTOY: tienda estática en GitHub Pages con Supabase.
Rama de trabajo: fix/revision-2. Nunca push a main.
Autor de los commits: Antonio Millan Rodríguez, antoniomillanr45@gmail.com. Sin Co-Authored-By ni enlaces de sesión.
Rutas relativas siempre. Sin frameworks ni dependencias nuevas.
js/datos.js es el único fichero que habla con Supabase.
La lógica de negocio va en SQL. Los cambios nuevos van en sql/11_ en adelante, idempotentes, sin pisar scripts anteriores.
No ejecutar nada contra la Supabase real.
Estado del trabajo en PROGRESO.md: actualizarlo tras cada tarea.
