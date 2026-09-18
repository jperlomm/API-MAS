import socket
import time
import struct
import threading
import sys

def handle_tcp():
    print("Iniciando servidor ToD (RFC 868) sobre TCP en puerto 37...")
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(('0.0.0.0', 37))
        s.listen(10)
    except Exception as e:
        print(f"Error fatal bindeando TCP puerto 37: {e}")
        sys.exit(1)
        
    while True:
        try:
            conn, addr = s.accept()
            # Diferencia exacta en segundos entre 01-Ene-1900 (ToD) y 01-Ene-1970 (Unix): 2208988800
            tod_time = int(time.time()) + 2208988800
            conn.sendall(struct.pack('!I', tod_time))
            conn.close()
        except Exception as e:
            print(f"Error de conexión TCP: {e}")

def handle_udp():
    print("Iniciando servidor ToD (RFC 868) sobre UDP en puerto 37...")
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.bind(('0.0.0.0', 37))
    except Exception as e:
        print(f"Error fatal bindeando UDP puerto 37: {e}")
        sys.exit(1)

    while True:
        try:
            data, addr = s.recvfrom(1024)
            # Diferencia exacta en segundos entre 01-Ene-1900 y 01-Ene-1970: 2208988800
            tod_time = int(time.time()) + 2208988800
            s.sendto(struct.pack('!I', tod_time), addr)
        except Exception as e:
            print(f"Error procesando datagrama UDP: {e}")

if __name__ == '__main__':
    # Iniciar TCP en un hilo y UDP en el hilo principal
    t_tcp = threading.Thread(target=handle_tcp, daemon=True)
    t_tcp.start()
    handle_udp()
