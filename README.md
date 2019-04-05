# Arquivos fonte

4 arquivos devem existir no diretorio `data`:

- `events.csv`
  Inclui eventos de compra e venda de ativos. Exemplo:

  ```
  "date","asset","category","quantity","price","brokerage"
  2013-09-17,"Acoes","PETR4","100","25,50",10
  2013-10-17,"Acoes","PETR4","-100","25,50",10
  2013-11-17,"Renda Fixa","Tesouro Selic 2025","15","100",0
  ```

- `ibovespa.csv`
  Inclui ações que fazem parte do índice Ibovespa, 1 por linha. Usado para marcar no html ações que são parte do índice.
- `indexes.csv`
  Inclui índices mensais para exibir no html gerado para comparar mês a mês. Exemplo:

  ```
  "date","index","value"
  "2018-08-30","IPCA","0,09"
  "2018-09-30","IBOVESPA","3,5"
  "2018-09-30","CDI","0,4681"
  ```

- `prices.csv`
  Inclui alterações de preços mês a mês para gerar os html para acompanhamento mensal. Exemplo:

  ```
  "date","asset","category","price"
  2019-02-28,"Tesouro Pre 2025","Renda Fixa","609,72"
  2019-03-19,PETR4,Acoes,"30,25"
  ```

# Gerar relatórios

`bin/invest` - gera os relatórios htmls baseado nos arquivos fonte
`bin/prices` - atualiza os preços das ações com o preço de hoje e salva em `prices.csv`
