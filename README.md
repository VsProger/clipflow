# ClipFlow

Нативный менеджер буфера обмена для macOS. Swift 6, SwiftUI + AppKit, SwiftData,
Swift Concurrency. Полностью локальный: ничего не покидает Mac.

Требования: macOS 14+, Xcode 16+.

## Сборка

Проект — набор исходников без `.xcodeproj` (его нет смысла держать в текстовом виде).
Сборка за пять минут:

1. Xcode → **File → New → Project → macOS → App**.
   Product Name: `ClipFlow`, Interface: **SwiftUI**, Language: **Swift**,
   Storage: **None**, Testing System: **None**.
2. Удалить сгенерированные `ClipFlowApp.swift` и `ContentView.swift`.
3. Перетащить папку `Sources` в проект (**Copy items if needed**, **Create groups**).
4. `Resources/Info.plist` — заменить сгенерированный или скопировать из него ключи;
   главное — `LSUIElement = YES`. `Resources/ClipFlow.entitlements` подключить
   в **Signing & Capabilities → App Sandbox**.
5. Build Settings:
   - `SWIFT_VERSION` = 6.0, `SWIFT_STRICT_CONCURRENCY` = complete
   - `MACOSX_DEPLOYMENT_TARGET` = 14.0
   - `GENERATE_INFOPLIST_FILE` = NO (используем свой Info.plist)
6. ⌘R. Иконка появится в menu bar, приложения в Dock не будет.

Автозапуск (`SMAppService`) требует подписанной сборки — в debug-сборке
без подписи тумблер вернётся в выключенное состояние, это нормально.

## Структура

```
Sources/
├── App/                  точка входа и композиционный корень
│   ├── main.swift            NSApplication (не SwiftUI App — см. комментарий в файле)
│   ├── AppDelegate.swift     жизненный цикл, fatal error UI
│   └── AppEnvironment.swift  DI, связывание сервисов, реакции на настройки
├── Models/
│   ├── ClipboardItem.swift   @Model: только метаданные
│   ├── ClipboardCapture.swift снимок буфера (Sendable value type)
│   └── Settings.swift        SettingsStore + типы настроек
├── Services/
│   ├── PasteboardReader.swift читает NSPasteboard, вся политика приватности
│   ├── ClipboardMonitor.swift адаптивный polling changeCount
│   ├── ClipboardStore.swift   SwiftData, дедупликация, лимиты
│   ├── ImageStorage.swift     actor: файлы изображений
│   ├── ThumbnailService.swift ImageIO, превью без полного декодирования
│   ├── SearchService.swift    индексация и ранжированный поиск
│   ├── RetentionService.swift планировщик автоочистки
│   ├── HotKeyManager.swift    RegisterEventHotKey
│   ├── PasteWriter.swift      запись в буфер, Copy as…, авто-вставка
│   └── LaunchAtLogin.swift    SMAppService
├── ViewModels/
│   └── ClipboardViewModel.swift
├── UI/
│   ├── Panel/                 NSPanel + перехват клавиатуры
│   ├── HistoryView.swift      список, поиск, empty state
│   ├── ItemRowView.swift      ряд, hover actions, контекстное меню
│   ├── PreviewOverlay.swift   увеличенный preview
│   ├── Settings/              4 таба + окно
│   ├── MenuBar/               NSStatusItem
│   └── Components/            превью-кеш, запись хоткея
└── Support/                   логирование, пути, хеши, классификация, key codes
```

Зависимостей нет — ни одного пакета.

## Данные

```
~/Library/Application Support/ClipFlow/     (в sandbox — внутри контейнера приложения)
├── ClipFlow.store          SwiftData: метаданные
├── Images/                 полноразмерные изображения
└── Thumbnails/             превью ≤ 320 px
```

Каталог создаётся с правами `0700` и помечен `isExcludedFromBackup`: история
буфера не уезжает в Time Machine и iCloud. Файлы удаляются вместе с записями;
при запуске выполняется сверка и удаление «сирот», оставшихся после аварийного
завершения.

## Клавиатура

| Клавиши | Действие |
|---|---|
| ⌘⇧V | открыть/закрыть историю (настраивается) |
| ↑ / ↓ | навигация, ⌘↑ / ⌘↓ — в начало/конец |
| ↩ | вставить в буфер и закрыть |
| ⌘⌫ | удалить элемент (⌫ — когда поиск пуст) |
| ⌘Y или Space | preview |
| ⌘P | pin / unpin |
| ⌘K | очистить поиск |
| ⎋ | очистить поиск → закрыть окно |

Фокус при открытии — в строке поиска; список при этом уже имеет выделение,
поэтому «⌘⇧V → ↩» работает без промежуточных нажатий.

## Что осознанно не сделано

- **Rich text / RTF, файлы, цвета.** `ItemKind` и `ClipboardCapture.Payload`
  расширяются добавлением case; `PasteboardReader` — единственное место,
  которое придётся тронуть.
- **Синхронизация между устройствами.** Противоречит privacy-модели;
  если понадобится — только end-to-end с явным opt-in.
- **OCR по скриншотам.** VisionKit позволяет искать по тексту на картинках;
  задел есть — `searchIndex` уже отдельное поле, дописывать в него можно
  постфактум.
- **Свой Quick Look.** Preview показывается оверлеем внутри панели: отдельное
  окно отобрало бы key-статус и сломало навигацию с клавиатуры.
