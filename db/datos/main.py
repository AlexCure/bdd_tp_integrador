from generar_datos import (
    generar_campos, generar_perfiles, generar_lotes, generar_pivote, generar_sectores,
    generar_asignaciones_pivote, generar_categorias_y_tipos, generar_variables_y_relacion,
    generar_dispositivos, generar_instalaciones, generar_gateways, generar_mediciones,
    generar_reglas_alarma, generar_alarma_dispositivo, generar_eventos_alarma, generar_usuarios, exportar_mediciones_csv, cur, conn,
)


def main():
    print("Generando campos...")
    ids_campo = generar_campos(3)

    print("Generando perfiles...")
    ids_perfil = generar_perfiles()

    print("Generando lotes...")
    lotes_por_campo = generar_lotes(ids_campo, por_campo=3)

    print("Generando sectores...")
    todos_los_lotes = [id_lote for lista in lotes_por_campo.values() for id_lote in lista]
    ids_sector = generar_sectores(todos_los_lotes, por_lote=2)

    print("Generando pivotes...")
    pivotes_por_campo = generar_pivote(ids_campo, por_campo=2)

    print("Generando asignaciones de pivote...")
    ids_asignacion = generar_asignaciones_pivote(pivotes_por_campo, lotes_por_campo)

    print(f"Listo: {len(ids_campo)} campos, {len(todos_los_lotes)} lotes, "
            f"{len(ids_sector)} sectores, {sum(len(v) for v in pivotes_por_campo.values())} pivotes, "
            f"{len(ids_asignacion)} asignaciones.")
    
    print("Generando categorías y tipos de dispositivo...")
    ids_tipo = generar_categorias_y_tipos()

    print("Generando variables...")
    ids_variable = generar_variables_y_relacion(ids_tipo)

    print("Generando dispositivos...")
    dispositivos_por_tipo = generar_dispositivos(ids_tipo, por_tipo=3)

    print("Generando instalaciones de dispositivos...")
    todos_los_pivotes = [id_pivote for lista in pivotes_por_campo.values() for id_pivote in lista]
    ids_instalacion = generar_instalaciones(dispositivos_por_tipo, ids_campo, ids_sector, todos_los_pivotes)

    print(f"Bloque 2 listo: {len(ids_tipo)} tipos, {len(ids_variable)} variables, "
            f"{sum(len(v) for v in dispositivos_por_tipo.values())} dispositivos, "
            f"{len(ids_instalacion)} instalaciones.")

    print("Generando gateways...")
    ids_gateway = generar_gateways(2)

    print("Generando mediciones (puede tardar unos segundos)...")
    ids_medicion = generar_mediciones(dispositivos_por_tipo, ids_gateway, cantidad=800)

    print(f"Bloque 3 listo: {len(ids_gateway)} gateways, {len(ids_medicion)} mediciones.")

    print("Generando reglas de alarma...")
    reglas_generadas = generar_reglas_alarma(ids_variable)

    print("Generando relación alarma-dispositivo...")
    # (id_regla, tipo_de_dispositivo_al_que_aplica) según el orden en que se definieron las reglas
    reglas_info = [
        (reglas_generadas[0][0], "Sonda de humedad"),        # Batería baja -> aplica a todos, uso sonda como ejemplo
        (reglas_generadas[1][0], "Sonda de humedad"),        # Temperatura suelo alta
        (reglas_generadas[2][0], "Sonda de humedad"),        # Humedad suelo baja
        (reglas_generadas[3][0], "Caudalímetro"),            # Caudal fuera de rango
    ]
    generar_alarma_dispositivo(reglas_info, dispositivos_por_tipo)

    print("Generando eventos de alarma...")
    ids_evento = generar_eventos_alarma(reglas_generadas, cantidad_por_regla=3)

    print(f"Bloque 4 listo: {len(reglas_generadas)} reglas, {len(ids_evento)} eventos.")
    
    print("Generando usuarios...")
    ids_usuario = generar_usuarios(ids_perfil, cantidad=6)

    print(f"Bloque 5 listo: {len(ids_usuario)} usuarios.")
    
    print("Exportando mediciones a CSV...")
    exportar_mediciones_csv()

    print("\n=== Generación completa ===")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
