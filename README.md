# Observability Notification
## Projeto de Código Aberto

<li>Autor: Richard Marques (richard@seberino.com.br)
<li>Criação: 08/06/2026

## 1 - Introdução

Este é um projeto de código aberto, disponível para forks ou contribuições. 
O propósito deste projeto é server como mecanismo de notificação para soluções como Dynatrace (nosso primeiro use case).

Mais informações visite o site do projeto
https://observability-notification.web.app

## 2 - Features da versão atual

1) Cadastro de instancias do Dynatrace
Aqui você pode adicionar suas instancias de Dynatrace, setar uma área gerenciada para restringir os problemas que você quer ver e também definir número de itens por página e se quer receber notificação por Push quando novos problemas forem abertos

2) Lista de instancias cadastradas
Aqui você acompanha a lista dos ambeintes que voc6e cadastrou, como o nome amigável dele e o total de alertas segundo o filtro escolhido
Nesta lista você pode fazer duas cosias: editar as configuraçòes do ambiente arrastando para a direita e escolhando a opção editar, ou clicar no nome do ambiente para ter acesso a lista de problemas abertos no momento

3) Lista de Problemas 
Nesta função você ve a lista de problemas abertos, como um icone indicando a severidade, a descrição do problema como filtro, em baixo a URL do ambiente, e por último o nome do recurso afetad por este problema
Nesta lista você pode escolher um item clicando em cima dele para ver o detalhe. 

4) Detalhe do Problema
Nesta tela é possível ler todas as primcipais informações do problema e tem acesso a dois botões: Abrir Dynatracce no Navegador, essta função abre um navegador no seu celular com a tela deo detalhe do problema na instancia Duynatrace SaaS. 
Outra ação que pode ser feita é compartilhar o link do proglema com algum coleta, por mensagem, email etc. 

## Requisitos
Para o aplicativo funcionar você precisa cadastrar ao menos 1 instancia Dynatrace e para isso você vai precisar das informações abaixo:
<li>a) Nome do ambiente (um nome amigável para reconhecer o ambiente na lista)
<li>b) URL (url do dynatrace, algo como https://teste.live.dynatrace.com). Substitua a palavra teste pelo nome da sua instancia.
<li>c) Itens por página daquela instancia
<li>d) API Token: Aqui é o Token gerado no Dynatrace com as permissões: Read Configurations, e Read Problems 
<li>e) Items per page: Aqui é o número máximo que você vai exibir por página na lista de Problemas. 
<li>f) Opcionalmente pode infromar o Managed Zone (durante o primeiro cadastro é necessário clicar em Fetch Zones para cagarregar a lista)

Além do cadastro do ambiente você vai precisar de sinal 5G, ou conexão via rede wi-fii
