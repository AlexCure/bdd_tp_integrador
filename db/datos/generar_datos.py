import os
from dotenv import load_dotenv
import psycopg2
from faker import Faker
import random
import json
from datetime import datetime, timedelta
import csv

load_dotenv()

conn = psycopg2.connect(
    host=os.getenv("DB_HOST"),
    port=os.getenv("DB_PORT"),
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD")
)
cur = conn.cursor()

fake = Faker("es_AR")

def generar_campos(cantidad):
    ids = []
    for _ in range(cantidad):
        nombre = f"Campo {fake.last_name()}"
        ubicacion = fake.city()
        superficie = round(random.uniform(50, 500), 2)
        cur.execute(
            "INSERT INTO campo (nombre, ubicacion, superficie) VALUES (%s, %s, %s) RETURNING id_campo",
            (nombre, ubicacion, superficie)
        )
        ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_perfiles():
    perfiles = [
        ("Operador", "Consulta dispositivos, mediciones, graficos, alarmas"),
        ("Configurador", "Ademas del operador, administra configuraciones y alarmas"),
        ("Administrador", "Ademas del configurador, administra usuarios y permisos")
    ]
    ids = {}
    for nombre, descripcion in perfiles:
        cur.execute(
            "INSERT INTO perfil (nombre, descripcion) VALUES (%s, %s) RETURNING id_perfil",
            (nombre, descripcion)
        )
        ids[nombre] = cur.fetchone()[0]
    conn.commit()
    return ids

def generar_lotes(ids_campo, por_campo=3):
    ids_por_campo = {}
    for id_campo in ids_campo:
        ids_por_campo[id_campo] = []
        for i in range(por_campo):
            nombre = str(i + 1)
            superficie = round(random.uniform(5, 50), 2)
            cur.execute(
                "INSERT INTO lote (id_campo, nombre, superficie) VALUES (%s, %s, %s) RETURNING id_lote",
                (id_campo, nombre, superficie)
            )
            ids_por_campo[id_campo].append(cur.fetchone()[0])
    conn.commit()
    return ids_por_campo

def generar_pivote(ids_campo, por_campo=2):
    ids_por_campo = {}
    for id_campo in ids_campo:
        ids_por_campo[id_campo] = []
        for i in range(por_campo):
            nombre = f"Pivote {i + 1}"
            fabricante = random.choice(["John Deere", "Valley", "Reinke", "Netafim"])
            modelo = f"Modelo {fake.random_int(min=100, max=999)}"
            cur.execute(
                "INSERT INTO pivote (id_campo, nombre, fabricante, modelo) VALUES (%s, %s, %s, %s) RETURNING id_pivote",
                (id_campo, nombre, fabricante, modelo)
            )
            ids_por_campo[id_campo].append(cur.fetchone()[0])
    conn.commit()
    return ids_por_campo

def generar_sectores(ids_lote, por_lote=2):
    ids = []
    for id_lote in ids_lote:
        for i in range(por_lote):
            nombre = chr(65 + i)
            cur.execute(
                "INSERT INTO sector (id_lote, nombre) VALUES (%s, %s) RETURNING id_sector",
                (id_lote, nombre)
            )
            ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_asignaciones_pivote(pivotes_por_campo, lotes_por_campo):
    ids = []
    for id_campo, ids_pivote in pivotes_por_campo.items():
        lotes_del_campo = lotes_por_campo[id_campo]
        for id_pivote in ids_pivote:
            id_lote = random.choice(lotes_del_campo)
            cur.execute(
                "INSERT INTO asignacion_pivote (id_pivote, id_lote) VALUES (%s, %s) RETURNING id_asignacion",
                (id_pivote, id_lote)
            )
            ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_categorias_y_tipos():
    categorias = {
        "Suelo": ["Sonda de humedad"],
        "Meteorológico": ["Estación meteorológica"],
        "Riego": ["Caudalímetro"],
    }
    ids_tipo = {}  # {"Sonda de humedad": id_tipo, ...}
    for nombre_categoria, tipos in categorias.items():
        cur.execute(
            "INSERT INTO categoria_dispositivo (nombre) VALUES (%s) RETURNING id_categoria",
            (nombre_categoria,)
        )
        id_categoria = cur.fetchone()[0]
        for nombre_tipo in tipos:
            cur.execute(
                "INSERT INTO tipo_dispositivo (id_categoria, nombre) VALUES (%s, %s) RETURNING id_tipo",
                (id_categoria, nombre_tipo)
            )
            ids_tipo[nombre_tipo] = cur.fetchone()[0]
    conn.commit()
    return ids_tipo

def generar_variables_y_relacion(ids_tipo):
    variables_por_tipo = {
        "Sonda de humedad": [("Humedad de suelo", "%"), ("Temperatura de suelo", "°C"), ("Conductividad eléctrica", "dS/m")],
        "Estación meteorológica": [("Temperatura", "°C"), ("Humedad relativa", "%"), ("Velocidad de viento", "km/h"), ("Radiación solar", "W/m²"), ("Precipitaciones", "mm")],
        "Caudalímetro": [("Caudal", "L/h")],
    }
    
    # Todos los dispositivos sensan batería (regla de dominio, CLAUDE.md)
    for tipos in variables_por_tipo.values():
        tipos.append(("Batería", "%"))
        
    ids_variable = {}  # nombre -> id_variable
    for nombre_tipo, variables in variables_por_tipo.items():
        id_tipo = ids_tipo[nombre_tipo]
        for nombre_var, unidad in variables:
            if nombre_var not in ids_variable:
                cur.execute(
                    "INSERT INTO variable (nombre, unidad) VALUES (%s, %s) RETURNING id_variable",
                    (nombre_var, unidad)
                )
                ids_variable[nombre_var] = cur.fetchone()[0]
            cur.execute(
                "INSERT INTO tipo_variable (id_tipo_dispositivo, id_variable) VALUES (%s, %s)",
                (id_tipo, ids_variable[nombre_var])
            )
    conn.commit()
    return ids_variable

def generar_dispositivos(ids_tipo, por_tipo=3):
    dispositivos_por_tipo = {}
    for nombre_tipo, id_tipo in ids_tipo.items():
        dispositivos_por_tipo[nombre_tipo] = []
        for _ in range(por_tipo):
            cur.execute(
                """INSERT INTO dispositivo
                    (id_tipo, fabricante, modelo, numero_serie, dev_eui, app_eui, app_key,
                    at_pin, ota_pin, intervalo_transmision, estado_operativo, estado_comunicacion)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    RETURNING id_dispositivo""",
                (
                    id_tipo,
                    random.choice(["Bosch", "Davis", "Decagon", "Sensirion"]),
                    f"Modelo-{fake.random_int(min=100, max=999)}",
                    fake.hexify(text="^^^^^^^^^^"),
                    fake.hexify(text="^^^^^^^^^^^^^^^^"),
                    fake.hexify(text="^^^^^^^^^^^^^^^^"),
                    fake.hexify(text="^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"),
                    fake.hexify(text="^^^^"),
                    fake.hexify(text="^^^^"),
                    random.choice([60, 300, 600]),
                    "on",
                    "connected",
                )
            )
            dispositivos_por_tipo[nombre_tipo].append(cur.fetchone()[0])
    conn.commit()
    return dispositivos_por_tipo

def generar_instalaciones(dispositivos_por_tipo, ids_campo, ids_sector, ids_pivote):
    lugar_por_tipo = {
        "Sonda de humedad": ("id_sector", ids_sector),
        "Estación meteorológica": ("id_campo", ids_campo),
        "Caudalímetro": ("id_pivote", ids_pivote),
    }
    ids = []
    for nombre_tipo, ids_dispositivo in dispositivos_por_tipo.items():
        columna_fk, ids_lugar = lugar_por_tipo[nombre_tipo]
        for id_dispositivo in ids_dispositivo:
            id_lugar = random.choice(ids_lugar)
            cur.execute(
                f"""INSERT INTO instalacion_dispositivo (id_dispositivo, {columna_fk})
                    VALUES (%s, %s) RETURNING id_instalacion""",
                (id_dispositivo, id_lugar)
            )
            ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_gateways(cantidad=2):
    ids = []
    for i in range(cantidad):
        cur.execute(
            "INSERT INTO gateway (nombre) VALUES (%s) RETURNING id_gateway",
            (f"Gateway {i + 1}",)
        )
        ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_valores_medidos(nombre_tipo):
    bateria = round(random.uniform(20, 100), 1)
    if nombre_tipo == "Sonda de humedad":
        return {
            "humedad_suelo": round(random.uniform(10, 60), 1),
            "temperatura_suelo": round(random.uniform(10, 35), 1),
            "conductividad_electrica": round(random.uniform(0.5, 3.0), 2),
            "bateria": bateria,
        }
    elif nombre_tipo == "Estación meteorológica":
        return {
            "temperatura": round(random.uniform(-5, 40), 1),
            "humedad_relativa": round(random.uniform(20, 100), 1),
            "velocidad_viento": round(random.uniform(0, 60), 1),
            "radiacion_solar": round(random.uniform(0, 1000), 1),
            "precipitaciones": round(random.uniform(0, 20), 1),
            "bateria": bateria,
        }
    elif nombre_tipo == "Caudalímetro":
        return {
            "caudal": round(random.uniform(0, 500), 1),
            "bateria": bateria,
        }
        
def generar_mediciones(dispositivos_por_tipo, ids_gateway, cantidad=800):
    tipo_por_dispositivo = {}
    for nombre_tipo, ids_dispositivo in dispositivos_por_tipo.items():
        for id_dispositivo in ids_dispositivo:
            tipo_por_dispositivo[id_dispositivo] = nombre_tipo

    todos_los_dispositivos = list(tipo_por_dispositivo.keys())
    ids = []
    contador = 1
    for _ in range(cantidad):
        id_dispositivo = random.choice(todos_los_dispositivos)
        nombre_tipo = tipo_por_dispositivo[id_dispositivo]
        id_gateway = random.choice(ids_gateway)
        fecha_hora = datetime.now() - timedelta(minutes=random.randint(0, 60 * 24 * 30))
        valores = generar_valores_medidos(nombre_tipo)

        cur.execute(
            """INSERT INTO medicion
                (id_dispositivo, id_gateway, fecha_hora, valores_medidos, rssi, snr, contador_mensajes)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id_medicion""",
            (
                id_dispositivo,
                id_gateway,
                fecha_hora,
                json.dumps(valores),
                round(random.uniform(-120, -60), 1),
                round(random.uniform(-20, 10), 1),
                contador,
            )
        )
        ids.append(cur.fetchone()[0])
        contador += 1
    conn.commit()
    return ids

def generar_reglas_alarma(ids_variable):
    reglas = [
        ("Batería baja", "Batería", 20, None, True),
        ("Temperatura suelo alta", "Temperatura de suelo", None, 35, True),
        ("Humedad suelo baja", "Humedad de suelo", 15, None, True),
        ("Caudal fuera de rango", "Caudal", 10, 450, True),
    ]
    reglas_generadas = []
    for descripcion, nombre_variable, umbral_inf, umbral_sup, habilitada in reglas:
        id_variable = ids_variable[nombre_variable]
        cur.execute(
            """INSERT INTO regla_alarma (id_variable, descripcion, umbral_inferior, umbral_superior, habilitada)
                VALUES (%s, %s, %s, %s, %s) RETURNING id_regla""",
            (id_variable, descripcion, umbral_inf, umbral_sup, habilitada)
        )
        id_regla = cur.fetchone()[0]
        reglas_generadas.append((id_regla, umbral_inf, umbral_sup))
    conn.commit()
    return reglas_generadas

def generar_alarma_dispositivo(reglas_info, dispositivos_por_tipo):
    for id_regla, nombre_tipo in reglas_info:
        for id_dispositivo in dispositivos_por_tipo[nombre_tipo]:
            cur.execute(
                "INSERT INTO alarma_dispositivo (id_regla_alarma, id_dispositivo) VALUES (%s, %s)",
                (id_regla, id_dispositivo)
            )
    conn.commit()

def generar_eventos_alarma(reglas_generadas, cantidad_por_regla=3):
    ids = []
    for id_regla, umbral_inf, umbral_sup in reglas_generadas:
        for _ in range(cantidad_por_regla):
            if umbral_inf is not None:
                valor = round(random.uniform(umbral_inf - 10, umbral_inf), 2)
            else:
                valor = round(random.uniform(umbral_sup, umbral_sup + 10), 2)
            fecha_hora = datetime.now() - timedelta(hours=random.randint(0, 24 * 15))
            cur.execute(
                "INSERT INTO evento_alarma (id_regla, fecha_hora, valor_detectado) VALUES (%s, %s, %s) RETURNING id_evento_alarma",
                (id_regla, fecha_hora, valor)
            )
            ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def generar_usuarios(ids_perfil, cantidad=6):
    ids = []
    for _ in range(cantidad):
        nombre = fake.first_name()
        apellido = fake.last_name()
        email = fake.unique.email()
        contrasena = fake.password(length=12)
        id_perfil = random.choice(list(ids_perfil.values()))
        cur.execute(
            "INSERT INTO usuario (nombre, apellido, email, contrasena, id_perfil) VALUES (%s, %s, %s, %s, %s) RETURNING id_usuario",
            (nombre, apellido, email, contrasena, id_perfil)
        )
        ids.append(cur.fetchone()[0])
    conn.commit()
    return ids

def exportar_mediciones_csv(ruta_salida="data/ejemplos/mediciones.csv"):
    cur.execute(
        """SELECT m.id_medicion, d.numero_serie, td.nombre AS tipo_dispositivo,
            m.fecha_hora, m.valores_medidos, m.rssi, m.snr, m.contador_mensajes
            FROM medicion m
            JOIN dispositivo d ON d.id_dispositivo = m.id_dispositivo
            JOIN tipo_dispositivo td ON td.id_tipo = d.id_tipo
            ORDER BY m.fecha_hora
            LIMIT 100"""
    )
    filas = cur.fetchall()
    columnas = [desc[0] for desc in cur.description]

    filas_convertidas = []
    for fila in filas:
        fila = list(fila)
        fila[4] = json.dumps(fila[4])
        filas_convertidas.append(fila)

    with open(ruta_salida, "w", newline="", encoding="utf-8") as archivo:
        escritor = csv.writer(archivo)
        escritor.writerow(columnas)
        escritor.writerows(filas_convertidas)

    print(f"Exportadas {len(filas)} mediciones a {ruta_salida}")