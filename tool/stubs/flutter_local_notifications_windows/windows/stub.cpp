// Заглушка для проверочной Windows-сборки AO Bible: настоящий код уведомлений Windows требует ATL
// (нет в установленных Build Tools). Уведомления нужны только на Android/iOS.
extern "C" __declspec(dllexport) int aob_notifications_stub() { return 0; }
