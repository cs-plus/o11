# Instalador automático do O11v4

Script Bash para instalar e configurar o O11v4 automaticamente no Ubuntu.

O instalador baixa o pacote do GitHub, solicita a senha do arquivo ZIP, configura o servidor de licença com PM2 e cria um serviço systemd para o O11v4.

## Sistemas compatíveis

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS
- Acesso como `root` ou usuário com `sudo`
- Arquitetura compatível com o executável presente no pacote

## O que o instalador faz

1. Solicita a senha do arquivo `o11v4.zip`.
2. Detecta automaticamente o IP público do servidor.
3. Permite confirmar ou alterar o IP detectado.
4. Solicita a porta HTTP do servidor de licença, usando `180` como padrão.
5. Solicita a porta do O11v4, usando `8484` como padrão.
6. Baixa o pacote diretamente do GitHub.
7. Valida a senha e descompacta o arquivo.
8. Copia os arquivos para `/home/o11v4`.
9. Instala Node.js, npm, PM2 e Express.
10. Configura o IP e as portas no `server.js` e no `run.sh`.
11. Inicia o servidor de licença no PM2 com o nome `licserver`.
12. Configura o PM2 para iniciar automaticamente com o sistema.
13. Cria e inicia o serviço `o11v4run.service`.
14. Cria um backup da instalação anterior antes de atualizar.

## Instalação

Baixe o instalador:

```bash
wget -O instalar-o11v4.sh https://raw.githubusercontent.com/cs-plus/o11/main/o11v4/instalar-o11v4.sh
```

> Se o endereço do repositório ou da branch for diferente, ajuste a URL acima.

Dê permissão de execução:

```bash
chmod +x instalar-o11v4.sh
```

Execute:

```bash
sudo ./instalar-o11v4.sh
```

O instalador apresentará perguntas semelhantes a estas:

```text
=== Instalador automático do O11v4 ===
Senha do arquivo o11v4.zip:
IP deste servidor [149.78.185.186]:
Porta HTTP da licença [180]:
Porta do O11 [8484]:
```

Pressione `Enter` para aceitar os valores exibidos entre colchetes.

Ao digitar a senha do ZIP, nenhum caractere será mostrado no terminal. Isso é normal e evita que a senha fique visível.

## Estrutura da instalação

| Item | Caminho ou identificação |
| --- | --- |
| Diretório do O11v4 | `/home/o11v4` |
| Servidor de licença | `/home/o11v4/server.js` |
| Script de inicialização | `/home/o11v4/run.sh` |
| Executável | `/home/o11v4/o11v4` |
| Processo PM2 | `licserver` |
| Serviço systemd | `o11v4run.service` |
| Serviço de inicialização do PM2 | `pm2-root.service` |

## Portas padrão

| Serviço | Porta padrão |
| --- | ---: |
| Licença HTTP | `180` |
| Licença HTTP adicional | `5454` |
| Licença HTTPS | `443` |
| O11v4 | `8484` |

A porta principal do O11v4 pode ser alterada durante a instalação. O instalador modifica automaticamente o parâmetro `-p` no `run.sh`.

## Verificação

Verifique o servidor de licença:

```bash
pm2 status licserver
```

Veja os logs do servidor de licença:

```bash
pm2 logs licserver
```

Verifique o serviço do O11v4:

```bash
systemctl status o11v4run.service --no-pager
```

Acompanhe os logs:

```bash
journalctl -u o11v4run.service -f
```

Confira as portas em uso:

```bash
ss -ltnp | grep -E ':180|:5454|:443|:8484'
```

Se você escolheu outra porta para o O11v4, substitua `8484` no comando.

## Comandos de gerenciamento

### Reiniciar o servidor de licença

```bash
pm2 restart licserver
pm2 save
```

### Reiniciar o O11v4

```bash
systemctl restart o11v4run.service
```

### Parar o O11v4

```bash
systemctl stop o11v4run.service
```

### Iniciar o O11v4

```bash
systemctl start o11v4run.service
```

## Atualização e reinstalação

O instalador pode ser executado novamente. Quando encontra uma instalação existente, cria automaticamente um backup com data e hora:

```text
/home/o11v4.backup-AAAAMMDD-HHMMSS
```

Exemplo:

```text
/home/o11v4.backup-20260902-183426
```

## Solução de problemas

### Porta já está em uso

Identifique o processo responsável, substituindo `180` pela porta desejada:

```bash
ss -ltnp 'sport = :180'
```

Se o processo for uma instância antiga do `licserver`, remova e recrie pelo PM2:

```bash
pm2 delete licserver
pm2 save --force
```

Depois execute novamente o instalador.

### O PM2 recria o processo após ele ser encerrado

Não mate apenas o PID do Node.js, pois o PM2 poderá iniciá-lo novamente. Gerencie o processo pelo próprio PM2:

```bash
pm2 stop licserver
pm2 delete licserver
pm2 save --force
```

### `Permission denied`

Adicione permissão de execução:

```bash
chmod +x instalar-o11v4.sh
```

### `./: Is a directory`

Não coloque espaço entre `./` e o nome do arquivo.

Incorreto:

```bash
./ instalar-o11v4.sh
```

Correto:

```bash
./instalar-o11v4.sh
```

### `sudo: unable to resolve host`

Confira o hostname:

```bash
hostname
```

Edite `/etc/hosts`:

```bash
sudo nano /etc/hosts
```

Adicione uma linha usando o hostname retornado pelo comando anterior:

```text
127.0.1.1 NOME-DO-SERVIDOR
```

### Avisos de montagem de `hls` e `dl`

O `run.sh` tenta montar estes diretórios:

```text
/home/o11v4/hls
/home/o11v4/dl
```

Se aparecer `can't find in /etc/fstab`, confira as configurações de montagem e o conteúdo do arquivo:

```bash
cat /etc/fstab
```

## Segurança

- A senha do ZIP é solicitada de forma interativa.
- A senha não é gravada no instalador.
- Não publique a senha no README, no script ou no histórico do Git.
- Restrinja no firewall apenas as portas que realmente precisam de acesso externo.
- Revise o conteúdo do pacote e do instalador antes de utilizá-los em produção.

## Arquivo de origem

O pacote utilizado pelo instalador está fixado neste commit:

```text
https://github.com/cs-plus/o11/blob/ce491a9006716f72fe057a0c26fc259549274cf4/o11v4.zip
```

Fixar o commit evita que uma alteração futura no repositório modifique silenciosamente o pacote instalado.

## Licença

Consulte os termos e a licença do projeto e dos arquivos distribuídos no repositório de origem antes do uso ou da redistribuição.
