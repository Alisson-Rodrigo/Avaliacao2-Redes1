#!/bin/bash

echo "==> 0. Limpeza Inicial"
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)
docker network rm lan1 lan2 lan3 lan4
docker system prune -f

echo "==> 1. Criando Redes"
docker network create --driver bridge --subnet=192.168.50.0/24 --gateway=192.168.50.1 lan1
docker network create --driver bridge --subnet=192.168.60.0/24 --gateway=192.168.60.1 lan2  
docker network create --driver bridge --subnet=192.168.70.0/24 --gateway=192.168.70.1 lan3
docker network create --driver bridge --subnet=192.168.80.0/24 --gateway=192.168.80.1 lan4

echo "==> 2. Criando Roteadores"
docker run -dit --name router1 --privileged --net lan1 --ip 192.168.50.10 ubuntu
docker run -dit --name router2 --privileged --net lan1 --ip 192.168.50.20 ubuntu
docker network connect --ip 192.168.60.10 lan2 router2
docker network connect --ip 192.168.70.10 lan3 router2
docker run -dit --name router3 --privileged --net lan1 --ip 192.168.50.30 ubuntu
docker network connect --ip 192.168.70.20 lan3 router3
docker network connect --ip 192.168.80.10 lan4 router3

echo "==> 3. Criando Hosts e Servidores Web"
docker run -dit --name host2 --privileged --net lan2 --ip 192.168.60.50 ubuntu
docker run -dit --name servidor_a --privileged --net lan2 --ip 192.168.60.100 -p 8081:80 nginx

docker run -dit --name host3 --privileged --net lan3 --ip 192.168.70.50 ubuntu
docker run -dit --name servidor_b --privileged --net lan3 --ip 192.168.70.100 -p 8082:80 nginx

docker run -dit --name host4 --privileged --net lan4 --ip 192.168.80.50 ubuntu
docker run -dit --name servidor_c --privileged --net lan4 --ip 192.168.80.100 -p 8083:80 nginx

echo "==> 4. Configurando Roteadores"
for r in router1 router2 router3; do
  docker exec -it $r bash -c "apt update && apt install net-tools iproute2 iputils-ping -y"
  docker exec -it $r bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
done

docker exec -it router1 bash -c "ip route add 192.168.60.0/24 via 192.168.50.20 && ip route add 192.168.70.0/24 via 192.168.50.20 && ip route add 192.168.80.0/24 via 192.168.50.30"
docker exec -it router2 bash -c "ip route add 192.168.80.0/24 via 192.168.50.30"
docker exec -it router3 bash -c "ip route add 192.168.60.0/24 via 192.168.50.20"

echo "==> 5. Configurando Hosts"
for h in host2 host3 host4; do
  docker exec -it $h bash -c "apt update && apt install net-tools iproute2 iputils-ping links -y"
done

docker exec -it host2 bash -c "ip route replace default via 192.168.60.10"
docker exec -it host3 bash -c "ip route replace default via 192.168.70.10"
docker exec -it host4 bash -c "ip route replace default via 192.168.80.10"

for h in host2 host3 host4; do
  docker exec -it $h bash -c "echo '192.168.60.100 www.sitea.com' >> /etc/hosts && echo '192.168.70.100 www.siteb.com' >> /etc/hosts && echo '192.168.80.100 www.sitec.com' >> /etc/hosts"
done

echo "==> 6. Configurando Páginas Personalizadas"

docker exec -it servidor_a bash -c "apt update && apt install vim -y && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site A</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#667eea,#764ba2);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}</style></head>
<body><h1>Site A</h1><p>IP: 192.168.60.100 | LAN1</p></body></html>
EOF
nginx -s reload"

docker exec -it servidor_b bash -c "apt update && apt install vim -y && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site B</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#667eea,#764ba2);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}</style></head>
<body><h1>Site B</h1><p>IP: 192.168.70.100 | LAN2</p></body></html>
EOF
nginx -s reload"

docker exec -it servidor_c bash -c "apt update && apt install vim -y && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site C</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#667eea,#764ba2);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}</style></head>
<body><h1>Site C</h1><p>IP: 192.168.80.100 | LAN3</p></body></html>
EOF
nginx -s reload"

echo "==> 7. Testes de Conectividade"

docker exec -it host2 ping -c 4 192.168.70.50
docker exec -it host2 ping -c 4 192.168.80.50
docker exec -it host3 ping -c 4 192.168.80.50

echo "==> Use 'docker exec -it host2 bash' e teste os sites com 'links http://sitea' etc."

echo "✅ Configuração finalizada com sucesso!"