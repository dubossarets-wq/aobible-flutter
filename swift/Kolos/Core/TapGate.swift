import QuartzCore

/// Замок нажатий в тексте: пока идёт прокрутка (и ещё полсекунды после неё) нажатия на слова, двойные и долгие нажатия
/// не срабатывают — палец только прокручивает. Прокрутка тут же стоит, если на остановившийся текст попал палец, и случайное
/// касание не открывает слово. Один на всё приложение (экран читает один человек одним пальцем)
enum TapGate {
    nonisolated(unsafe) private static var blockedUntil: CFTimeInterval = 0
    /// Пауза после прокрутки
    private static let quiet: CFTimeInterval = 0.5

    /// Можно ли сейчас реагировать на нажатие
    static var open: Bool { CACurrentMediaTime() >= blockedUntil }

    /// Прокрутка началась или идёт. Верхний предел — страховка: если конец прокрутки потерялся, замок сам откроется
    static func scrolling() { blockedUntil = CACurrentMediaTime() + 4 }

    /// Прокрутка закончилась: ещё quiet секунд замок закрыт
    static func scrollEnded() { blockedUntil = CACurrentMediaTime() + quiet }
}
