import socket

SERVER_IP = "127.0.0.1"   # Troque pelo IP do servidor se estiver em outra máquina
SERVER_PORT = 6789

clientSock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

while True:
    msg = input("Digite um número (ou 'sair'): ")
    if msg.lower() == "sair":
        break

    clientSock.sendto(msg.encode(), (SERVER_IP, SERVER_PORT))
    data, _ = clientSock.recvfrom(1024)
    print("Resposta:", data.decode())