# Agents 2.0 — Документация

Agents 2.0 — это командная оркестрационная система на базе OpenRouter. В отличие от v1, здесь задачи маршрутизируются не к отдельным агентам, а к **специализированным командам** — каждая со своим Lead, системным промптом, памятью и fallback-цепочкой моделей.

---

## Архитектура системы

```
User Task
    |
    v
dispatch.sh (Orchestrator v2)
    |
    +--[--new-project?]--> planning/director.sh
    |                           |
    |                      вывод включается в контекст задачи
    |
    v
decomposer (deepseek-chat)
Разбивает задачу на подзадачи по командам, возвращает JSON
    |
    v
┌──────────────────────────────────────────────────────────────┐
│  Параллельное выполнение команд (max 6 concurrent)           │
│                                                              │
│  frontend/lead.sh   backend/lead.sh   security/lead.sh ...  │
│       |                  |                  |               │
│  prompt_engineer    prompt_engineer    prompt_engineer       │
│       |                  |                  |               │
│  primary model      primary model      primary model        │
│       |    [fail]        |    [fail]        |    [fail]     │
│  fallback1          fallback1          fallback1            │
│       |    [fail]        |    [fail]        |    [fail]     │
│  fallback2          fallback2          fallback2            │
│       |                  |                  |               │
│  memory_append      memory_append      memory_append        │
└──────────────────────────────────────────────────────────────┘
    |
    v
synthesizer (gpt-4o)
Объединяет все результаты в единый структурированный ответ
    |
    +--[--audit?]--> audit/lead.sh
    |                    |
    |               аудит качества и безопасности
    |
    v
Final Answer + Report Table
```

---

## Отличия от Agents v1

| Критерий | v1 (agents/) | v2 (agents2/) |
|----------|-------------|---------------|
| Единица выполнения | Отдельный агент (`roles/*.sh`) | Команда (`teams/*/lead.sh`) |
| Системный промпт | Фиксированный в роли | Специализированный для команды |
| Fallback моделей | Нет (один вызов) | Три уровня: primary → fallback1 → fallback2 |
| Память | Нет | `teams/*/memory.md` — персистентная между сессиями |
| Prompt engineering | Автоматический внутри каждой роли | Автоматический внутри каждой команды через `lib/prompt_engineer.sh` |
| Флаги оркестратора | Нет | `--new-project`, `--audit`, `--teams`, `--no-pe` |
| Логирование | Одна строка на вызов | Две лог-файла: `.log` (oneliner) + `.full.log` (детальный) |
| Декомпозиция | По агентам | По командам с командным контекстом |
| Конфигурация | `config.json` с агентами | `config.json` с командами и моделями |

---

## Команды — полный список

### Технические команды

#### `frontend` — UI/UX и фронтенд
- **Область**: React, Vue, CSS, Tailwind, accessibility, web performance, SSR/SSG
- **Primary model**: `openai/gpt-4o-mini`
- **Fallback**: `google/gemini-2.0-flash-001` → `deepseek/deepseek-chat`
- **Когда использовать**: компоненты, стили, UX-решения, анимации, бандлинг

#### `backend` — API и серверная логика
- **Область**: REST/GraphQL API, микросервисы, аутентификация, базы данных (ORM, SQL), очереди
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o-mini` → `google/gemini-2.0-flash-001`
- **Когда использовать**: бизнес-логика, эндпоинты, интеграции, server-side код

#### `devops` — Инфраструктура и CI/CD
- **Область**: Docker, Kubernetes, GitHub Actions, деплой, мониторинг, IaC (Terraform)
- **Primary model**: `openai/gpt-4o-mini`
- **Fallback**: `deepseek/deepseek-chat` → `google/gemini-2.0-flash-001`
- **Когда использовать**: пайплайны, контейнеризация, деплой, настройка серверов

#### `security` — Безопасность
- **Область**: OWASP Top 10, пен-тест, уязвимости, threat modeling, проверка auth
- **Primary model**: `openai/gpt-4o`
- **Fallback**: `google/gemini-2.0-flash-001` → `deepseek/deepseek-chat`
- **Когда использовать**: ревью кода на уязвимости, аудит эндпоинтов, проверка секретов

#### `qa` — Тестирование
- **Область**: unit-тесты, интеграционные тесты, E2E (Playwright, Cypress), тест-планы
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o-mini` → `google/gemini-2.0-flash-001`
- **Когда использовать**: генерация тестов, тест-планы, edge cases, QA-процессы

#### `mobile` — Мобильная разработка
- **Область**: iOS (Swift), Android (Kotlin), React Native, Flutter, App Store / Play Market
- **Primary model**: `openai/gpt-4o-mini`
- **Fallback**: `deepseek/deepseek-chat` → `google/gemini-2.0-flash-001`
- **Когда использовать**: мобильные компоненты, нативные API, публикация, mobile UX

#### `data` — Данные и базы данных
- **Область**: SQL-оптимизация, схемы БД, дата-пайплайны, ETL, аналитика на уровне данных
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o-mini` → `google/gemini-2.0-flash-001`
- **Когда использовать**: проектирование схем, медленные запросы, миграции, data warehouse

#### `aiml` — AI и машинное обучение
- **Область**: ML-модели, обучение, инференс, архитектура AI, LLM-интеграции, embeddings, RAG
- **Primary model**: `openai/gpt-4o`
- **Fallback**: `deepseek/deepseek-chat` → `openai/gpt-4o-mini`
- **Когда использовать**: AI-функциональность в продукте, файн-тюнинг, векторные БД, промпт-инжиниринг

---

### Бизнес и стратегические команды

#### `analyst` — Бизнес-аналитика
- **Область**: анализ метрик, market research, конкурентный анализ, инсайты из данных
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o-mini` → `google/gemini-2.0-flash-001`
- **Когда использовать**: разбор KPI, анализ воронки, метрики продукта, бизнес-анализ

#### `strategy` — Стратегия
- **Область**: GTM-стратегия, позиционирование, конкурентное преимущество, роадмап бизнеса
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o` → `openai/gpt-4o-mini`
- **Когда использовать**: выход на рынок, ценообразование, партнёрства, стратегические решения

#### `writer` — Тексты и контент
- **Область**: копирайтинг, документация, блог, emails, отчёты, пресс-релизы
- **Primary model**: `openai/gpt-4o`
- **Fallback**: `deepseek/deepseek-chat` → `openai/gpt-4o-mini`
- **Когда использовать**: любой письменный контент — от changelog до pitch deck

#### `planner` — Планирование
- **Область**: проектное планирование, спринт-планирование, декомпозиция задач, таймлайны
- **Primary model**: `deepseek/deepseek-chat`
- **Fallback**: `openai/gpt-4o-mini` → `google/gemini-2.0-flash-001`
- **Когда использовать**: роадмапы, milestone-планы, оценка задач, структура проекта

---

### Оркестрационные модули

| Модуль | Модель | Назначение |
|--------|--------|-----------|
| `decomposer` | `deepseek/deepseek-chat` | Разбивает задачу на подзадачи по командам, возвращает JSON |
| `synthesizer` | `openai/gpt-4o` | Объединяет все результаты команд в единый ответ |
| `lib/prompt_engineer.sh` | `openai/gpt-4o` | Оптимизирует промпт перед отправкой в каждую команду |
| `planning/director.sh` | `openai/gpt-4o` | Pre-project анализ: vision, архитектура, риски (флаг `--new-project`) |
| `audit/lead.sh` | `openai/gpt-4o` | Финальный аудит: качество, безопасность, пробелы (флаг `--audit`) |

---

## Использование dispatch.sh

### Базовые примеры

```bash
# Передать задачу текстом
~/.agents2/dispatch.sh "спроектируй REST API для системы управления задачами"

# Передать через stdin
echo "нужен анализ конкурентов в нише AI-инструментов для разработчиков" | ~/.agents2/dispatch.sh

# Передать файл как контекст
cat requirements.md | ~/.agents2/dispatch.sh "реализуй это"

# Совместить аргумент и файл
cat brief.txt | ~/.agents2/dispatch.sh "разработай стратегию запуска"
```

### Флаги

#### `--new-project` — запуск нового проекта

Перед декомпозицией запускает `planning/director.sh`, который выдаёт:
- Видение и цели проекта
- Предлагаемую архитектуру
- Риски и зависимости
- Рекомендованный стек

Его вывод добавляется в контекст задачи для всех команд.

```bash
~/.agents2/dispatch.sh --new-project "создай SaaS-платформу для управления инвойсами"
~/.agents2/dispatch.sh --new-project "мобильное приложение для трекинга питания"
```

#### `--audit` — аудит после выполнения

После синтеза результатов запускает `audit/lead.sh`, который:
- Проверяет полноту ответа
- Ищет противоречия между командами
- Выявляет пробелы в безопасности
- Оценивает качество предложенных решений

```bash
~/.agents2/dispatch.sh --audit "спроектируй систему авторизации"
~/.agents2/dispatch.sh --audit "напиши архитектуру микросервисов для платёжного модуля"
```

#### `--teams LIST` — принудительные команды

Пропускает декомпозицию, напрямую запускает указанные команды. Полезно, когда ты точно знаешь, что нужно.

```bash
# Только backend и security
~/.agents2/dispatch.sh --teams "backend,security" "аудит платёжного API"

# Frontend и qa
~/.agents2/dispatch.sh --teams "frontend,qa" "ревью компонента авторизации"

# Все аналитические команды
~/.agents2/dispatch.sh --teams "analyst,strategy,planner" "анализ рынка для запуска в Германии"
```

#### `--no-pe` — отключить prompt engineering

Пропускает шаг оптимизации промпта (быстрее, менее точно).

```bash
~/.agents2/dispatch.sh --no-pe "быстрый вопрос: какой HTTP код для rate limiting?"
```

#### Комбинирование флагов

```bash
# Новый проект + аудит
~/.agents2/dispatch.sh --new-project --audit "создай систему управления пользователями"

# Принудительные команды + аудит
~/.agents2/dispatch.sh --teams "backend,security" --audit "реализуй JWT авторизацию"

# Новый проект + конкретные команды
~/.agents2/dispatch.sh --new-project --teams "backend,devops,security" "деплой на AWS EKS"
```

---

## Примеры по типам задач

### Разработка продукта

```bash
# Полный цикл нового фичи
~/.agents2/dispatch.sh --new-project "добавить систему подписок с Stripe"

# Архитектурный ревью + аудит безопасности
~/.agents2/dispatch.sh --audit "проверь мою текущую архитектуру аутентификации" < src/auth/

# Ревью PR перед мержем
cat changes.diff | ~/.agents2/dispatch.sh --teams "backend,security,qa" "ревью этих изменений"
```

### Бизнес и стратегия

```bash
# GTM-стратегия
~/.agents2/dispatch.sh "план выхода на немецкий рынок с B2B SaaS-продуктом"

# Анализ падения метрик
echo "retention упал с 60% до 40% за последние 2 месяца" | \
    ~/.agents2/dispatch.sh --teams "analyst,strategy" "найди причины и предложи решения"

# Планирование запуска
~/.agents2/dispatch.sh --new-project --teams "strategy,planner,writer" \
    "подготовь план запуска ProductHunt"
```

### Контент и документация

```bash
# Техническая документация
cat src/api/ | ~/.agents2/dispatch.sh --teams "writer,backend" "напиши API-документацию"

# Питч-дек
~/.agents2/dispatch.sh --teams "strategy,writer,analyst" "напиши питч для Series A"

# Cold email последовательность
~/.agents2/dispatch.sh --teams "writer,strategy" \
    "создай 5-шаговую email-последовательность для enterprise CTOs"
```

---

## Как работает память команд

Каждая команда хранит персистентный файл памяти:
- Регулярные команды: `~/.agents2/teams/<team>/memory.md`
- Специальные команды: `~/.agents2/planning/memory.md`, `~/.agents2/audit/memory.md`

**Жизненный цикл памяти:**
1. Перед выполнением — `memory_read` загружает текущую память в контекст
2. Во время выполнения — память включается в системный промпт как дополнительный контекст
3. После выполнения — `memory_append` добавляет новую запись с датой и кратким описанием задачи

**Лимиты и сжатие:**
- `MAX_LINES=40` — жёсткий лимит на количество строк
- `TRIM_TO=35` — оставляем последние N строк при превышении
- `SUMMARIZE_AT=30` — при достижении порога вызывается `memory_summarize` (GPT-4o-mini сжимает историю до 20 пунктов)

**Просмотр памяти команды:**

```bash
cat ~/.agents2/teams/backend/memory.md
cat ~/.agents2/teams/security/memory.md
cat ~/.agents2/planning/memory.md
```

**Очистить память команды:**

```bash
# Сбросить файл (создастся заново при следующем запуске)
rm ~/.agents2/teams/backend/memory.md
```

---

## Как работает fallback-цепочка

Каждая команда настроена с тремя моделями. При сбое основной автоматически пробуется следующая:

```
primary model
    |
    | [fail / empty / timeout]
    v
fallback1 model
    |
    | [fail / empty / timeout]
    v
fallback2 model
    |
    | [fail]
    v
ERROR: все модели недоступны
```

**Логика сбоя:**
- HTTP 429 (rate limit) → retry через 5 секунд, затем fallback
- HTTP 5xx → немедленный fallback
- Пустой ответ → считается сбоем, fallback
- Timeout (60 сек) → fallback

**Экспортируемые переменные после выполнения:**
- `FALLBACK_USED_MODEL` — какая модель фактически ответила
- `FALLBACK_ATTEMPTS` — сколько попыток потребовалось

**Текущие fallback-цепочки по командам:**

| Команда | Primary | Fallback 1 | Fallback 2 |
|---------|---------|------------|------------|
| frontend | gpt-4o-mini | gemini-2.0-flash | deepseek-chat |
| backend | deepseek-chat | gpt-4o-mini | gemini-2.0-flash |
| devops | gpt-4o-mini | deepseek-chat | gemini-2.0-flash |
| security | gpt-4o | gemini-2.0-flash | deepseek-chat |
| qa | deepseek-chat | gpt-4o-mini | gemini-2.0-flash |
| mobile | gpt-4o-mini | deepseek-chat | gemini-2.0-flash |
| data | deepseek-chat | gpt-4o-mini | gemini-2.0-flash |
| aiml | gpt-4o | deepseek-chat | gpt-4o-mini |
| analyst | deepseek-chat | gpt-4o-mini | gemini-2.0-flash |
| strategy | deepseek-chat | gpt-4o | gpt-4o-mini |
| writer | gpt-4o | deepseek-chat | gpt-4o-mini |
| planner | deepseek-chat | gpt-4o-mini | gemini-2.0-flash |

---

## Добавление новой команды

Чтобы добавить команду `payments`:

### 1. Создать директорию и файлы

```bash
mkdir -p ~/.agents2/teams/payments
```

### 2. Создать `lead.sh`

Скопируй любой существующий lead.sh как шаблон и измени:

```bash
cp ~/.agents2/teams/backend/lead.sh ~/.agents2/teams/payments/lead.sh
chmod +x ~/.agents2/teams/payments/lead.sh
```

В файле измени:
- `TEAM="payments"`
- `PRIMARY_MODEL`, `FALLBACK1_MODEL`, `FALLBACK2_MODEL` — нужные модели
- `TEAM_SYSTEM_PROMPT` — экспертный системный промпт для команды

### 3. Создать `memory.md`

```bash
cat > ~/.agents2/teams/payments/memory.md << 'EOF'
# Team Memory: payments
Last updated: 2026-03-26 00:00

## Accumulated Knowledge
EOF
```

### 4. Добавить команду в `config.json`

```json
"payments": {
  "description": "Payment systems, Stripe, invoicing, billing, PCI DSS",
  "models": {
    "primary": "openai/gpt-4o",
    "fallback1": "deepseek/deepseek-chat",
    "fallback2": "openai/gpt-4o-mini"
  }
}
```

### 5. Добавить команду в список декомпозера

В `dispatch.sh` найди строку с `DECOMPOSER_SYSTEM` и добавь в список Teams:

```
- payments   : платёжные системы, Stripe, биллинг, инвойсинг, PCI DSS
```

### 6. Добавить в множество `VALID_TEAMS` в Python-блоке dispatch.sh

```python
VALID_TEAMS = {
    "frontend", "backend", "devops", "security", "qa",
    "mobile", "data", "aiml", "analyst", "strategy", "writer", "planner",
    "payments"  # <-- добавить
}
```

Готово. Команда доступна через `--teams payments` или будет автоматически выбираться декомпозером.

---

## Логирование

Все действия логируются автоматически в `~/.agents2/logs/`:

```bash
# Краткий лог (по одной строке на вызов)
cat ~/.agents2/logs/session_20260326.log

# Детальный лог (промпты + ответы)
cat ~/.agents2/logs/session_20260326.full.log
```

Формат краткого лога:
```
[2026-03-26 14:22:01] [backend:lead] [deepseek/deepseek-chat] [SUCCESS] Task summary... | prompt preview | response preview
```

---

## Troubleshooting

### "Error: OPENROUTER_API_KEY is not set"

```bash
# Установить в текущей сессии
export OPENROUTER_API_KEY=sk-or-ваш-ключ

# Установить постоянно
echo 'export OPENROUTER_API_KEY=sk-or-ваш-ключ' >> ~/.agents2/.env
```

Ключ доступен на https://openrouter.ai/keys

---

### "Decomposer returned invalid JSON"

Декомпозер вернул некорректный JSON (редкий сбой deepseek). dispatch.sh автоматически:
1. Определяет наиболее подходящую команду по ключевым словам в задаче
2. Запускает одну команду вместо параллельного выполнения

Если это происходит часто — проверь баланс на OpenRouter.

---

### Команда зависла или вернула пустой ответ

Таймаут на команду — 90 секунд. После этого fallback не применяется на уровне dispatch (только внутри самой команды). Команда вернёт `[team timed out after 90s]`.

Синтезатор включит эту информацию и пропустит недоступную команду.

---

### "lead.sh not found"

Команда отсутствует в `~/.agents2/teams/`. Либо создай её (см. раздел "Добавление новой команды"), либо используй флаг `--teams` с существующими командами.

---

### Старый dispatch.sh из .agents/ запускается вместо нового

Убедись, что вызываешь правильный путь:

```bash
# Agents 2.0 (командный)
~/.agents2/dispatch.sh "задача"

# Agents 1.0 (агентный, старый)
~/.agents/dispatch.sh "задача"
```

Если нужно заменить v1 alias на v2:

```bash
echo 'alias dispatch="~/.agents2/dispatch.sh"' >> ~/.bashrc
source ~/.bashrc
```

---

## Требования

- **Bash** 4.0+ (на macOS установи через `brew install bash`)
- **Python 3** (стандартная библиотека, без зависимостей)
- **OPENROUTER_API_KEY** — один ключ для всех моделей
- **chmod +x** на всех `.sh` файлах (выполняется при установке)

---

## Структура директории

```
~/.agents2/
├── dispatch.sh              ← главный оркестратор (этот файл запускаешь)
├── call_model.sh            ← прямой вызов модели через OpenRouter
├── config.json              ← конфигурация команд и моделей
├── AGENTS.md                ← эта документация
├── .env                     ← OPENROUTER_API_KEY (не в git!)
│
├── lib/
│   ├── logger.sh            ← логирование (oneliner + full)
│   ├── fallback.sh          ← fallback-цепочка моделей
│   ├── memory.sh            ← работа с командной памятью
│   └── prompt_engineer.sh   ← оптимизация промптов
│
├── teams/
│   ├── frontend/
│   │   ├── lead.sh          ← Team Lead (оркестратор команды)
│   │   └── memory.md        ← персистентная память команды
│   ├── backend/
│   ├── devops/
│   ├── security/
│   ├── qa/
│   ├── mobile/
│   ├── data/
│   ├── aiml/
│   ├── analyst/
│   ├── strategy/
│   ├── writer/
│   └── planner/
│
├── planning/
│   ├── director.sh          ← Pre-project директор (--new-project)
│   └── memory.md
│
├── audit/
│   ├── lead.sh              ← Аудит-лид (--audit)
│   └── memory.md
│
└── logs/
    ├── session_20260326.log       ← краткий лог
    └── session_20260326.full.log  ← детальный лог с промптами
```
