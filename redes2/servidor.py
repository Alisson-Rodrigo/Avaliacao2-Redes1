import socket
import math

HOST = "0.0.0.0"
PORT = 6789

serverSock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
serverSock.bind((HOST, PORT))
serverSock.settimeout(2.0)  # não fica bloqueado para sempre

print(f"Servidor UDP rodando em {HOST}:{PORT}... (Ctrl+C para sair)")

try:
    while True:
        try:
            data, addr = serverSock.recvfrom(1024)  # espera até 2s
        except socket.timeout:
            continue  # volta e espera de novo

        msg = data.decode().strip()
        print(f"📩 Recebido de {addr}: {msg}")

        try:
            n = int(msg)
            if n < 0:
                resposta = "Erro: fatorial não definido para negativos"
            else:
                resposta = f"Fatorial de {n} = {math.factorial(n)}"
        except ValueError:
            resposta = "Erro: envie um inteiro válido"

        serverSock.sendto(resposta.encode(), addr)
        print(f"📤 Enviado para {addr}: {resposta}")

except KeyboardInterrupt:
    print("\nEncerrando servidor...")
finally:
    serverSock.close()