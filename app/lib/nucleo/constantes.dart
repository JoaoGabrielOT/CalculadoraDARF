// Constantes de cálculo e de classificação (nucleo.py:16-24, 459, 539).

const double taxaB3Swing = 0.0003; // 0,0300% por operação (compra e venda)
const double taxaB3Daytrade = 0.00023; // 0,0230% por operação (compra e venda)

/// Variável como no Python: os testes mudam o valor.
double corretagemPorOrdem = 0.0;

const double aliqSwing = 0.15;
const double aliqDaytrade = 0.20;
const double irrfSwing = 0.00005; // 0,005% sobre o valor da venda
const double irrfDaytrade = 0.01; // 1% sobre o lucro do dia
const double limiteIsencao = 20000.0;
const double darfMinimo = 10.0;
const int diasLiquidacao = 2;
const List<String> sufixosBdr = ['31', '32', '33', '34', '35', '39'];
