#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Tamanho inicial desejado, em pixels lógicos.
constexpr int kLarguraInicial = 1360;
constexpr int kAlturaInicial = 860;
// Folga entre a janela e as bordas da área útil, em pixels lógicos.
constexpr int kMargem = 10;

// Reduz o tamanho inicial para caber na área útil (sem a barra de tarefas) do
// monitor em que a janela abre, considerando a escala de DPI; o Win32Window
// recebe valores lógicos e os multiplica pela escala do monitor.
void AjustarJanelaInicial(Win32Window::Point *origin, Win32Window::Size *size) {
  POINT ponto = {static_cast<LONG>(origin->x), static_cast<LONG>(origin->y)};
  HMONITOR monitor = ::MonitorFromPoint(ponto, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {sizeof(MONITORINFO)};
  if (!::GetMonitorInfo(monitor, &info)) {
    return;  // sem informação do monitor, mantém o tamanho padrão
  }
  double escala = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  if (escala <= 0) {
    return;
  }
  const RECT &area = info.rcWork;
  int largura_util =
      static_cast<int>((area.right - area.left) / escala) - 2 * kMargem;
  int altura_util =
      static_cast<int>((area.bottom - area.top) / escala) - 2 * kMargem;
  *origin = Win32Window::Point(
      static_cast<unsigned int>(std::max(0, static_cast<int>(area.left / escala)) + kMargem),
      static_cast<unsigned int>(std::max(0, static_cast<int>(area.top / escala)) + kMargem));
  // piso para uma área útil minúscula ou inválida
  largura_util = std::max(largura_util, 640);
  altura_util = std::max(altura_util, 480);
  *size = Win32Window::Size(
      static_cast<unsigned int>(std::min(kLarguraInicial, largura_util)),
      static_cast<unsigned int>(std::min(kAlturaInicial, altura_util)));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(kLarguraInicial, kAlturaInicial);
  AjustarJanelaInicial(&origin, &size);
  if (!window.Create(L"Calculadora DARF", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
