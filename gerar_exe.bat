@echo off
cd /d "%~dp0"

set PY=
where py >nul 2>nul && set PY=py
if not defined PY where python >nul 2>nul && set PY=python
if not defined PY (
    echo Python nao encontrado. Instale em https://www.python.org/downloads/
    echo Na instalacao, marque a opcao "Add python.exe to PATH".
    pause
    exit /b 1
)

for %%F in (nucleo.py google_sync.py mercado.py noticias.py tema.py componentes.py atualizador.py versao.py assets\icone.ico) do (
    if not exist %%F (
        echo Arquivo %%F nao encontrado nesta pasta.
        pause
        exit /b 1
    )
)

set CRED=
if exist credentials.json (
    set CRED=--add-data "credentials.json;."
    echo credentials.json encontrado: sera embutido no executavel.
) else (
    echo AVISO: credentials.json nao encontrado. O login com Google nao vai funcionar.
)

%PY% -m pip install --upgrade pyinstaller -r requirements.txt || goto erro
%PY% -m PyInstaller --onefile --noconsole --clean --collect-data customtkinter --collect-all yfinance --collect-all curl_cffi --icon assets\icone.ico --add-data "assets\icone.ico;assets" --add-data "assets\icone_janela.png;assets" %CRED% --name CalculadoraDARF calculadora_darf.py || goto erro

echo.
echo Executavel gerado em: %~dp0dist\CalculadoraDARF.exe
pause
exit /b 0

:erro
echo.
echo Falha ao gerar o executavel.
pause
exit /b 1
