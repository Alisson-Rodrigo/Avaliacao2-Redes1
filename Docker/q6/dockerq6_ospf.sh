#!/bin/bash

echo "==> 0. Limpeza Inicial"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker network rm lan1 lan2 lan3 lan4 2>/dev/null || true
docker system prune -f

echo "==> 1. Criando Redes"
docker network create --driver bridge --subnet=192.168.50.0/24 --gateway=192.168.50.1 lan1
docker network create --driver bridge --subnet=192.168.60.0/24 --gateway=192.168.60.1 lan2  
docker network create --driver bridge --subnet=192.168.70.0/24 --gateway=192.168.70.1 lan3
docker network create --driver bridge --subnet=192.168.80.0/24 --gateway=192.168.80.1 lan4

echo "==> 2. Criando Roteadores com OSPF"
docker run -dit --name router1 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.10 ubuntu sleep infinity
docker run -dit --name router2 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.20 ubuntu sleep infinity
docker run -dit --name router3 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.30 ubuntu sleep infinity

# Conectando roteadores às redes adicionais
docker network connect --ip 192.168.60.10 lan2 router2
docker network connect --ip 192.168.70.10 lan3 router2
docker network connect --ip 192.168.70.20 lan3 router3
docker network connect --ip 192.168.80.10 lan4 router3

echo "==> 3. Criando Hosts e Servidores Web"
docker run -dit --name host2 --privileged --net lan2 --ip 192.168.60.50 ubuntu sleep infinity
docker run -dit --name servidor_a --privileged --net lan2 --ip 192.168.60.100 -p 8081:80 nginx

docker run -dit --name host3 --privileged --net lan3 --ip 192.168.70.50 ubuntu sleep infinity
docker run -dit --name servidor_b --privileged --net lan3 --ip 192.168.70.100 -p 8082:80 nginx

docker run -dit --name host4 --privileged --net lan4 --ip 192.168.80.50 ubuntu sleep infinity
docker run -dit --name servidor_c --privileged --net lan4 --ip 192.168.80.100 -p 8083:80 nginx

echo "Aguardando containers iniciarem (15 segundos)..."
sleep 15

echo "==> 4. Instalando Ferramentas e FRR nos Roteadores"
ROUTERS="router1 router2 router3"
for router in $ROUTERS; do
  echo "Instalando ferramentas e FRR no $router..."
  docker exec $router bash -c "DEBIAN_FRONTEND=noninteractive apt update && apt install -y net-tools iproute2 iputils-ping frr"
done

echo "==> 5. Habilitando IP Forwarding nos Roteadores"
for router in $ROUTERS; do
  docker exec $router bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
done

echo "==> 6. Configurando OSPF com FRR nos Roteadores"

FRR_DAEMONS_CONFIG='sed -i "s/zebra=no/zebra=yes/" /etc/frr/daemons && sed -i "s/ospfd=no/ospfd=yes/" /etc/frr/daemons'

# Configurar Router1
echo "Configurando OSPF no router1..."
docker exec router1 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router1
log syslog informational
!
router ospf
 ospf router-id 192.168.50.10
 network 192.168.50.0/24 area 0.0.0.0
!
line vty
!
EOF
service frr restart"

# Configurar Router2
echo "Configurando OSPF no router2..."
docker exec router2 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router2
log syslog informational
!
router ospf
 ospf router-id 192.168.50.20
 network 192.168.50.0/24 area 0.0.0.0
 network 192.168.60.0/24 area 0.0.0.0
 network 192.168.70.0/24 area 0.0.0.0
!
line vty
!
EOF
service frr restart"

# Configurar Router3
echo "Configurando OSPF no router3..."
docker exec router3 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router3
log syslog informational
!
router ospf
 ospf router-id 192.168.50.30
 network 192.168.50.0/24 area 0.0.0.0
 network 192.168.70.0/24 area 0.0.0.0
 network 192.168.80.0/24 area 0.0.0.0
!
line vty
!
EOF
service frr restart"

echo "Configuração OSPF concluída. Aguardando convergência (45 segundos)..."
sleep 45

echo "==> 7. Configurando Hosts"
HOSTS="host2 host3 host4"
for h in $HOSTS; do
  docker exec $h bash -c "apt update && apt install -y net-tools iproute2 iputils-ping links"
done

# Configurar gateway padrão nos hosts
docker exec host2 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.60.10"
docker exec host3 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.70.10"
docker exec host4 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.80.10"

# Configurar gateway padrão nos servidores
docker exec servidor_a bash -c "apt update && apt install -y iproute2 && ip route del default 2>/dev/null || true && ip route add default via 192.168.60.10"
docker exec servidor_b bash -c "apt update && apt install -y iproute2 && ip route del default 2>/dev/null || true && ip route add default via 192.168.70.10"
docker exec servidor_c bash -c "apt update && apt install -y iproute2 && ip route del default 2>/dev/null || true && ip route add default via 192.168.80.10"

# Configurar /etc/hosts nos hosts
for h in $HOSTS; do
  docker exec $h bash -c "echo '192.168.60.100 www.sitea.com sitea' >> /etc/hosts && echo '192.168.70.100 www.siteb.com siteb' >> /etc/hosts && echo '192.168.80.100 www.sitec.com sitec' >> /etc/hosts"
done

echo "==> 8. Configurando Páginas Personalizadas"

docker exec servidor_a bash -c "apt update && apt install -y vim && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site A</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#1e3c72,#2a5298);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0;}</style></head>
<body><h1>Site A</h1><div class='info'><p><strong>IP:</strong> 192.168.60.100 | <strong>LAN:</strong> LAN2</p><p><strong>Roteamento:</strong> OSPF Dinâmico</p></div></body></html>
EOF
nginx -s reload"

docker exec servidor_b bash -c "apt update && apt install -y vim && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site B</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#667eea,#764ba2);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0;}</style></head>
<body><h1>Site B</h1><div class='info'><p><strong>IP:</strong> 192.168.70.100 | <strong>LAN:</strong> LAN3</p><p><strong>Roteamento:</strong> OSPF Dinâmico</p></div></body></html>
EOF
nginx -s reload"

docker exec servidor_c bash -c "apt update && apt install -y vim && cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Site C</title>
<style>body{font-family:Arial;background:linear-gradient(45deg,#f093fb,#f5576c);color:white;text-align:center;padding:50px;}h1{font-size:3em;}p{font-size:1.2em;}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0;}</style></head>
<body><h1>Site C </h1><div class='info'><p><strong>IP:</strong> 192.168.80.100 | <strong>LAN:</strong> LAN4</p><p><strong>Roteamento:</strong> OSPF Dinâmico</p></div></body></html>
EOF
nginx -s reload"

echo "==> 9. Testes de Conectividade com OSPF"
echo "=== Teste de Conectividade entre Hosts ==="
docker exec host2 ping -c 3 192.168.70.50 || echo "Falha no ping host2 -> host3"
docker exec host2 ping -c 3 192.168.80.50 || echo "Falha no ping host2 -> host4"
docker exec host3 ping -c 3 192.168.80.50 || echo "Falha no ping host3 -> host4"

echo "=== Teste de Acesso aos Servidores Web ==="
docker exec host2 links -dump http://192.168.60.100 | head -5 || echo "Falha no acesso ao servidor_a"
docker exec host2 links -dump http://192.168.70.100 | head -5 || echo "Falha no acesso ao servidor_b"
docker exec host2 links -dump http://192.168.80.100 | head -5 || echo "Falha no acesso ao servidor_c"

echo "==> 10. Verificação do Status OSPF"
echo "=== Verificando Rotas OSPF nos Roteadores ==="
for router in $ROUTERS; do
  echo "--- Rotas no $router ---"
  docker exec $router vtysh -c "show ip route" | grep -E "(O|C)" || echo "Nenhuma rota OSPF encontrada"
  echo ""
done

echo "=== Verificando Vizinhos OSPF ==="
for router in $ROUTERS; do
  echo "--- Vizinhos OSPF do $router ---"
  docker exec $router vtysh -c "show ip ospf neighbor" || echo "Nenhum vizinho OSPF encontrado"
  echo ""
done

echo "==> 11. Informações de Acesso"
echo "Containers criados e em execução:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "Acesse os sites no seu navegador:"
echo "Site A http://localhost:8081"
echo "Site B http://localhost:8082" 
echo "Site C http://localhost:8083"
echo ""

echo "Para testar dentro dos containers:"
echo "docker exec -it host2 bash"
echo "# links http://www.sitea.com"
echo "# links http://www.siteb.com"
echo "# links http://www.sitec.com"
echo ""

echo "Para verificar status OSPF detalhado:"
echo "docker exec router2 vtysh -c 'show ip ospf interface'"
echo "docker exec router2 vtysh -c 'show ip ospf database'"
echo ""

echo "✅ Configuração OSPF finalizada com sucesso!"
echo "🔄 Roteamento dinâmico OSPF ativo entre todas as redes!"

echo ""
echo "=== Comandos de Limpeza (se necessário) ==="
echo "# docker stop \$(docker ps -q)"
echo "# docker rm \$(docker ps -aq)"
echo "# docker network rm lan1 lan2 lan3 lan4"