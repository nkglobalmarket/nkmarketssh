#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Scripti kaydetme komutu
sudo cp "$0" /usr/local/bin/nkmarketvip

# NK MARKET SUNUCU KURUCU

while true; do
    clear
    echo "----NK MARKET SUNUCU KURUCU----"
    echo "1. ssh kur"
    echo "2. x-ui kur"
    echo "3. nkmarket güncelle"
    echo "4. cik"
    
    read -p "Secenek girin (1/2/3/4): " option

    case $option in
        1)
            echo "ssh kur secildi."
            echo "Calisan komut: apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus && chmod 777 Plus && ./Plus"
            apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus && chmod 777 Plus && ./Plus
            ;;
        2)
            echo "x-ui kur secildi."
            echo "Calisan komut: apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus && chmod 777 Plus && ./Plus"
            apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/kiritosshxd/SSHPLUS/master/Plus && chmod 777 Plus && ./Plus
            ;;
        3)
            echo "nkmarket güncelle secildi."
            echo "Calisan komut: apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/nkglobalmarket/SSHPLUS/master/nkmarket.sh && chmod 777 nkmarket.sh && ./nkmarket.sh"
            apt update -y && apt upgrade -y && wget https://raw.githubusercontent.com/nkglobalmarket/SSHPLUS/master/nkmarket.sh && chmod 777 nkmarket.sh && ./nkmarket.sh
            ;;
        4)
            echo "Cikis secildi. Script kapatiliyor."
            exit 0
            ;;
        *)
            echo "Gecersiz secenek. Tekrar deneyin."
            ;;
    esac

    read -p "Devam etmek icin bir tusa basin..."
done