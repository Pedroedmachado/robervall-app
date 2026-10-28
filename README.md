# Robervall

App de orçamentos, vistorias e sinistros para oficina — Android, Windows e Linux (Flutter). Funciona offline; os dados ficam no aparelho.

## O que tem
- **Painel**: abertos, aguardando aprovação, em reparo, atrasados, valor em aberto, a receber de seguradoras, fechado no mês, próximas entregas.
- **Sinistros/orçamentos**: busca por placa, cliente, nº, seguradora; filtros por status e tipo (particular, seguradora, terceiro, frota); fluxo de status com histórico.
- **Dados**: cliente, seguradora, apólice, regulador/perito, franquia, veículo com **consulta à Tabela FIPE**.
- **Mapa de avarias**: toque nas partes do carro (leve/média/pesada) e gere os itens do orçamento automaticamente.
- **Fotos**: câmera/galeria, categorias (avaria, geral, documento, antes, depois), legenda, visualizador com zoom.
- **Orçamento**: troca (T), reparo (R), pintura (P) e serviço (S); origem da peça, horas de MO por tipo, horas de pintura + material, desconto por item e geral, itens aprovados/não aprovados, franquia, divisão seguradora × cliente, **alerta de perda total** (% da FIPE).
- **PDF**: orçamento ou laudo de vistoria sem preços, com fotos — imprimir, compartilhar ou salvar.
- **Catálogo** próprio de peças e serviços, **cadastros** (clientes, seguradoras, reguladores, fornecedores), **ajustes** (valor hora, numeração, dados da oficina, tema) e **backup .zip** para levar os dados do celular ao PC.

## Baixar
Cada push na `main` compila no GitHub Actions e publica em **Releases**: `Robervall-android.apk`, `Robervall-windows-x64.zip`, `Robervall-linux-x64.tar.gz`.

## Compilar na sua máquina
```bash
bash tool/prepare_platforms.sh   # gera android/, linux/, windows/
flutter pub get
flutter test
flutter run                       # ou: flutter build apk / linux / windows
```
