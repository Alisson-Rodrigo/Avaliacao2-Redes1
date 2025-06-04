#!/bin/bash

echo "==> 0. Limpeza Inicial"
docker stop $(docker ps -aq) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker network rm lan1 lan2 lan3 lan4 2>/dev/null
docker system prune -f

echo "==> 1. Criando Redes"
docker network create --driver bridge --subnet=192.168.50.0/24 --gateway=192.168.50.1 lan1
docker network create --driver bridge --subnet=192.168.60.0/24 --gateway=192.168.60.1 lan2  
docker network create --driver bridge --subnet=192.168.70.0/24 --gateway=192.168.70.1 lan3
docker network create --driver bridge --subnet=192.168.80.0/24 --gateway=192.168.80.1 lan4

echo "==> 2. Criando Roteadores"
docker run -dit --name router1 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.10 ubuntu:latest sleep infinity
docker run -dit --name router2 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.20 ubuntu:latest sleep infinity
docker network connect --ip 192.168.60.10 lan2 router2
docker network connect --ip 192.168.70.10 lan3 router2
docker run -dit --name router3 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.50.30 ubuntu:latest sleep infinity
docker network connect --ip 192.168.70.20 lan3 router3
docker network connect --ip 192.168.80.10 lan4 router3

echo "==> 3. Criando Hosts e Servidores Web"
docker run -dit --name host2 --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.60.50 ubuntu:latest sleep infinity
docker run -dit --name servidor_a --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.60.100 -p 8081:80 nginx:latest

docker run -dit --name host3 --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.70.50 ubuntu:latest sleep infinity
docker run -dit --name servidor_b --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.70.100 -p 8082:80 nginx:latest

docker run -dit --name host4 --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.80.50 ubuntu:latest sleep infinity
docker run -dit --name servidor_c --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.80.100 -p 8083:80 nginx:latest

echo "Aguardando containers iniciarem (15 segundos)..."
sleep 15

echo "==> 4. Instalando Ferramentas e FRR nos Roteadores"
ROUTERS="router1 router2 router3"
for router in $ROUTERS; do
  echo "Instalando ferramentas e FRR no $router..."
  docker exec $router bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y iproute2 iputils-ping net-tools frr"
done

echo "==> 5. Instalando Ferramentas nos Hosts"
HOSTS="host2 host3 host4"
for host in $HOSTS; do
  echo "Instalando ferramentas no $host..."
  docker exec $host bash -c "apt-get update && apt-get install -y iproute2 iputils-ping net-tools links"
done

echo "==> 6. Instalando Ferramentas nos Servidores Web"
WEBSERVERS="servidor_a servidor_b servidor_c"
for webserver in $WEBSERVERS; do
  echo "Instalando ferramentas no $webserver..."
  docker exec $webserver bash -c "apt-get update && apt-get install -y iproute2 iputils-ping net-tools vim"
done

echo "==> 7. Habilitando IP Forwarding nos Roteadores"
for router in $ROUTERS; do
  docker exec $router bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
done

echo "==> 8. Configurando RIP com FRR nos Roteadores"
FRR_DAEMONS_CONFIG='sed -i "s/zebra=no/zebra=yes/" /etc/frr/daemons && sed -i "s/ripd=no/ripd=yes/" /etc/frr/daemons'

# Configurar Router 1
echo "Configurando FRR no router1..."
docker exec router1 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router1
log syslog informational
!
router rip
 version 2
 network 192.168.50.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

# Configurar Router 2
echo "Configurando FRR no router2..."
docker exec router2 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router2
log syslog informational
!
router rip
 version 2
 network 192.168.50.0/24
 network 192.168.60.0/24
 network 192.168.70.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

# Configurar Router 3
echo "Configurando FRR no router3..."
docker exec router3 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname router3
log syslog informational
!
router rip
 version 2
 network 192.168.50.0/24
 network 192.168.70.0/24
 network 192.168.80.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

echo "Configuração RIP (FRR) concluída e serviços reiniciados."
echo "Aguardando convergência do RIP (20 segundos)..."
sleep 20

echo "==> 9. Configurando Gateway Padrão nos Hosts"
docker exec host2 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.60.10"
docker exec host3 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.70.10"
docker exec host4 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.80.10"

echo "==> 10. Configurando Gateway Padrão nos Servidores Web"
docker exec servidor_a bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.60.10"
docker exec servidor_b bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.70.10"
docker exec servidor_c bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.80.10"

echo "==> 11. Configurando /etc/hosts nos Containers"
ETC_HOSTS_ENTRIES="192.168.60.100 www.sitea.com sitea\n192.168.70.100 www.siteb.com siteb\n192.168.80.100 www.sitec.com sitec"

for container_name in host2 host3 host4 router1 router2 router3; do
  echo -e "$ETC_HOSTS_ENTRIES" | docker exec -i $container_name bash -c "cat >> /etc/hosts"
done

echo "==> 12. Configurando Páginas Personalizadas dos Servidores Web"

docker exec servidor_a bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Site A</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Site A</h1>
        <div class="info">
            <p><strong>IP:</strong> 192.168.60.100</p>
            <p><strong>Rede:</strong> LAN2</p>
            <p><strong>Domínio:</strong> www.sitea.com</p>
        </div>
        <p>Servidor A funcionando perfeitamente!</p>
    </div>
</body>
</html>
EOF
nginx -s reload'

docker exec servidor_b bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Site B</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Site B</h1>
        <div class="info">
            <p><strong>IP:</strong> 192.168.70.100</p>
            <p><strong>Rede:</strong> LAN3</p>
            <p><strong>Domínio:</strong> www.siteb.com</p>
        </div>
        <p>Servidor B operacional!</p>
    </div>
</body>
</html>
EOF
nginx -s reload'

docker exec servidor_c bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Site C</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 3em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Site C</h1>
        <div class="info">
            <p><strong>IP:</strong> 192.168.80.100</p>
            <p><strong>Rede:</strong> LAN4</p>
            <p><strong>Domínio:</strong> www.sitec.com</p>
        </div>
        <p>Servidor C ativo e funcionando!</p>
    </div>
</body>
</html>
EOF
nginx -s reload'

echo "==> 13. Configurar /etc/hosts na Máquina Host"
echo "Lembre-se de configurar o arquivo hosts da sua máquina:"
echo "127.0.0.1 www.sitea.com"
echo "127.0.0.1 www.siteb.com" 
echo "127.0.0.1 www.sitec.com"
echo ""

echo "==> 14. Testes de Conectividade (via RIP com FRR)"
echo "=== Teste de Conectividade entre Hosts ==="
docker exec host2 ping -c 3 192.168.70.50
docker exec host2 ping -c 3 192.168.80.50
docker exec host3 ping -c 3 192.168.80.50
echo ""

echo "=== Teste de Acesso por IP ==="
docker exec host2 links -dump http://192.168.60.100
docker exec host2 links -dump http://192.168.70.100
docker exec host2 links -dump http://192.168.80.100
echo ""

echo "=== Teste de Acesso por Domínio ==="
docker exec host2 links -dump http://www.sitea.com
docker exec host3 links -dump http://www.siteb.com
docker exec host4 links -dump http://www.sitec.com
echo ""

echo "==> 15. Acesso da Máquina Host"
echo "Acesse os sites no seu navegador:"
echo "Site A: http://localhost:8081  OU  http://www.sitea.com:8081"
echo "Site B: http://localhost:8082  OU  http://www.siteb.com:8082"
echo "Site C: http://localhost:8083  OU  http://www.sitec.com:8083"
echo ""

echo "==> 16. Verificação Final (RIP com FRR)"
echo "Verificar status dos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "Verificar redes:"
docker network ls | grep lan
echo ""

echo "=== Rotas e Status RIP nos Roteadores (FRR) ==="
for router in $ROUTERS; do
  echo "--- $router (vtysh -c 'show ip route') ---"
  docker exec $router vtysh -c "show ip route"
  sleep 1
  echo "--- $router (vtysh -c 'show ip rip status') ---"
  docker exec $router vtysh -c "show ip rip status"
  sleep 1
  echo "--- $router (vtysh -c 'show ip rip') ---"
  docker exec $router vtysh -c "show ip rip"
  sleep 1
done
echo ""

echo "✅ Configuração finalizada com sucesso usando RIP com FRR!"
echo ""
echo "Use 'docker exec -it host2 bash' e teste os sites com 'links http://www.sitea.com' etc."
echo ""

echo "### Comandos de Limpeza (Se Necessário) ###"
echo "# Para limpar o ambiente:"
echo "# docker stop \$(docker ps -q --filter \"name=router*\" --filter \"name=host*\" --filter \"name=servidor_*\")"
echo "# docker rm \$(docker ps -aq --filter \"name=router*\" --filter \"name=host*\" --filter \"name=servidor_*\")"
echo "# docker network rm lan1 lan2 lan3 lan4"