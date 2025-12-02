#!/bin/bash
# =====================================================
# SCRIPT DE DESPLIEGUE AUTOMÁTICO DESDE S3 HACIA EC2
# Autor: Wilder Duarte
# Fecha: $(date +"%Y-%m-%d")
# Descripción:
#   - Instala dependencias
#   - Descarga y despliega aplicación desde S3
#   - Registra logs locales y en S3
# =====================================================

# Archivo de log local
LOG_FILE="/var/log/deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== INICIO DEL DESPLIEGUE ====="

# Actualiza el sistema e instala dependencias
echo "Actualizando sistema e instalando dependencias..."
yum update -y
yum install -y httpd aws-cli unzip

# Inicia y habilita Apache
echo "Iniciando servicio Apache..."
systemctl enable httpd
systemctl start httpd

# Configuración del bucket y archivo
BUCKET="s3-og"
ZIPFILE="project.zip"
BASE=web
DEST="/var/www/html"

echo "Bucket configurado: $BUCKET"
echo "Archivo a desplegar: $ZIPFILE"

# Descargar archivo ZIP desde S3
echo "Descargando $ZIPFILE desde S3..."
aws s3 cp s3://$BUCKET/$ZIPFILE /tmp/$ZIPFILE

# Verificar si la descarga fue exitosa
if [ ! -f /tmp/$ZIPFILE ]; then
    echo "ERROR: No se pudo descargar el archivo $ZIPFILE desde S3."
    exit 1
fi

# Descomprimir en la raíz del servidor web
echo "Descomprimiendo archivo..."
unzip -o /tmp/$ZIPFILE -d $DEST

if [ -d "$DEST/$BASE" ]; then
    echo "Reorganizando estructura del proyecto..."
    mv $DEST/$BASE/* $DEST/
    rm -rf $DEST/$BASE
fi

# Ajustar permisos para Apache
echo "Ajustando permisos..."
chown -R apache:apache $DEST
find $DEST -type d -exec chmod 755 {} \;
find $DEST -type f -exec chmod 644 {} \;

# Obtener token IMDSv2 para metadata
echo "Obteniendo metadata de la instancia..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
FECHA=$(date +"%Y-%m-%d_%H-%M-%S")

# Crear archivo de estado visible en el sitio web
echo "Creando archivo de estado en el sitio web..."
cat <<EOF > $DEST/status.txt
<h2>Aplicación desplegada correctamente desde S3 ($ZIPFILE)</h2>
<p>Fecha de despliegue: $FECHA</p>
<p>Instancia: $INSTANCE_ID</p>
<p>IP Pública: $PUBLIC_IP</p>
<p>IP Privada: $PRIVATE_IP</p>
EOF

# Crear contenido del log local
echo "Generando registro del despliegue..."
LOG_CONTENT="Despliegue exitoso:
Fecha: $FECHA
Instancia: $INSTANCE_ID
IP Privada: $PRIVATE_IP
IP Pública: $PUBLIC_IP
Archivo desplegado: $ZIPFILE
Bucket origen: $BUCKET
------------------------------------------"

# Guardar log localmente (además del log general)
echo "$LOG_CONTENT" > /tmp/deploy-log.txt

# Subir log a S3 dentro de la carpeta logs
echo "Subiendo log a S3..."
aws s3 cp /tmp/deploy-log.txt s3://$BUCKET/logs/deploy_${INSTANCE_ID}_${FECHA}.txt

echo "===== DESPLIEGUE FINALIZADO CON ÉXITO ====="
