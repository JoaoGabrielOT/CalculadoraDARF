/// google_sync.py:4-11, com `drive.readonly` no lugar de
/// `drive.metadata.readonly` (o Python 1.12 segue com o antigo): a aba
/// Relatórios lista e baixa arquivos criados por outro cliente. Tokens antigos
/// continuam renovando, porque a renovação não pede `scope` e o token guarda os
/// escopos concedidos; só os Relatórios pedem o login de novo.
const escoposGoogle = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

/// Escopo que a aba Relatórios exige no token.
const escopoRelatorios = 'https://www.googleapis.com/auth/drive.readonly';

/// Escopo que só a conta dona da pasta de relatórios pede ("Permitir" na tela
/// de Amigos), para compartilhá-la com os amigos; fora de [escoposGoogle].
const escopoDrive = 'https://www.googleapis.com/auth/drive';

const urlSheets = 'https://sheets.googleapis.com/v4/spreadsheets';
const urlDrive = 'https://www.googleapis.com/drive/v3';
