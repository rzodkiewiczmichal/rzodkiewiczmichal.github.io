# Thread Safety in Java: From Volatile to Atomic Types

**Date:** 2026-03-04
**Source:** Production concurrency debugging, SonarQube rule java:S3077
**Tags:** #java #concurrency #volatile #atomic #thread-safety #jmm #best-practices

---

## Introduction

**Hook:** Your application passes all unit tests, integration tests pass with flying colors, code review looks perfect. You deploy to production and suddenly - race conditions, null pointer exceptions under load, metrics showing wrong counts. The debugger shows nothing. Welcome to concurrency bugs.

**Why it matters:** Concurrency bugs are among the hardest defects to diagnose in production. They manifest intermittently, disappear under debugger scrutiny, and only surface under real-world load. The root cause is almost always the same: shared mutable state accessed by multiple threads without proper synchronization. A single misunderstood `volatile` keyword can cause production outages.

**What you'll learn:** How the Java Memory Model works, when `volatile` is sufficient and when it's dangerously insufficient, why double-checked locking is fragile, and how `AtomicReference` provides safer lazy initialization that makes thread safety a property of the type rather than a calling convention.

---

## The Problem

Consider a common pattern: lazy initialization in a component that can't use dependency injection. A JAX-RS client filter needs a `TracingService` instance, but filters are constructed by the runtime, so dependencies must be resolved lazily:

```java
public abstract class AbstractTracingFilter {
    private TracingService tracingService;

    protected TracingService getTracingService() {
        if (tracingService == null) {
            tracingService = new TracingService();
        }
        return tracingService;
    }
}
```

In a single-threaded world, this works perfectly. In a production application server where dozens of request-handling threads access this concurrently, it's broken.

### Why This Is Problematic

- **Visibility issue** - Thread A writes `tracingService = new TracingService()`, but Thread B may continue reading `null` from its CPU cache indefinitely. Modern CPUs don't read from main memory directly.
- **Race condition** - Multiple threads see `null` simultaneously and all create their own `TracingService` instance, leading to multiple instances where only one was intended.
- **No atomicity** - The check `if (tracingService == null)` and the assignment `tracingService = new TracingService()` are separate operations. Between them, another thread can interfere.
- **Production-only bug** - Works perfectly in tests with few threads, fails intermittently under production load with dozens of concurrent requests.
- **Silent failure** - No compilation warnings, no test failures, just wrong behavior that's nearly impossible to debug.

### Understanding the Root Cause: Java Memory Model

Modern CPUs maintain cache hierarchies (L1, L2, L3) per core. The Java Memory Model (JMM) defines when writes by one thread become visible to other threads. Without explicit synchronization, the JMM makes **no guarantee** about visibility.

The JMM uses **happens-before** relationships. A write in Thread A is visible to Thread B only if there's a happens-before edge:
- `synchronized` blocks - unlocking a monitor happens-before subsequent locking
- `volatile` fields - write happens-before any subsequent read
- `java.util.concurrent` utilities - establish happens-before edges internally

---

## The Solution

Use **atomic types** from `java.util.concurrent.atomic` package. These types make thread safety a property of the data type itself, not a calling convention that every access site must remember.

### Atomic Types Overview

```java
// Instead of volatile + synchronized
public abstract class AbstractTracingFilter {
    private final AtomicReference<TracingService> tracingServiceRef = new AtomicReference<>();

    protected TracingService getTracingService() {
        TracingService service = tracingServiceRef.get();
        if (service == null) {
            tracingServiceRef.compareAndSet(null, new TracingService());
            service = tracingServiceRef.get();
        }
        return service;
    }
}
```

### Key Atomic Types

| Type | Wraps | Key Operations |
|------|-------|----------------|
| `AtomicBoolean` | `boolean` | `get()`, `set()`, `compareAndSet()` |
| `AtomicInteger` | `int` | `get()`, `set()`, `incrementAndGet()`, `compareAndSet()` |
| `AtomicLong` | `long` | Same as `AtomicInteger` |
| `AtomicReference<V>` | Object reference | `get()`, `set()`, `compareAndSet()` |

### Why This Works Better

- **Lock-free** - Built on CPU-level Compare-And-Swap (CAS) instruction, no blocking
- **Self-contained safety** - Thread safety is in the type itself, cannot be bypassed accidentally
- **Simple to reason about** - Each operation has clear, well-documented semantics
- **No forgotten synchronization** - The field is `final AtomicReference`, you must use its methods
- **Better under contention** - Multiple threads make progress independently without blocking

### Understanding Compare-And-Swap (CAS)

All atomic types use a single CPU instruction: Compare-And-Swap.

```
CAS(address, expectedValue, newValue):
    atomically {
        if *address == expectedValue:
            *address = newValue
            return true
        else:
            return false
    }
```

This is hardware-level (x86: `CMPXCHG`, ARM: `LDREX/STREX`) and non-blocking. If two threads CAS simultaneously, one succeeds immediately, the other fails immediately - no waiting.

---

## Real-World Example

A JAX-RS filter that traces HTTP traffic to external APIs. Filters are constructed by the runtime (not dependency injection), so the tracing service must be lazily initialized.

### Before (Problematic - Double-Checked Locking)

```java
public abstract class AbstractTracingFilter {
    private volatile TracingService tracingService;

    protected TracingService getTracingService() {
        if (tracingService == null) {                    // First check (no lock)
            synchronized (this) {
                if (tracingService == null) {            // Second check (with lock)
                    tracingService = new TracingService();
                }
            }
        }
        return tracingService;
    }
}
```

Problems with this approach:
- **Fragile correctness** - Removing `volatile` silently breaks it, bug won't show in tests
- **Mixed concerns** - Uses `volatile` for visibility but `synchronized` for atomicity
- **Not self-documenting** - Field doesn't communicate "lazily initialized exactly once"
- **Error-prone** - New method accessing the field without synchronized guard introduces race
- **SonarQube rule java:S3077** - "Use a thread-safe type; `volatile` is not enough"

### After (Improved - AtomicReference)

```java
public abstract class AbstractTracingFilter {
    private final AtomicReference<TracingService> tracingServiceRef = new AtomicReference<>();

    protected TracingService getTracingService() {
        TracingService service = tracingServiceRef.get();
        if (service == null) {
            tracingServiceRef.compareAndSet(null, new TracingService());
            service = tracingServiceRef.get();
        }
        return service;
    }
}
```

Benefits of this approach:
- **Lock-free** - No synchronized block, better performance under contention
- **Type-safe** - Cannot accidentally read field directly, must use atomic methods
- **Self-contained** - Thread safety is in the type, not calling convention
- **Clear semantics** - Each operation has well-documented behavior
- **Passes SonarQube** - Recommended pattern for lazy initialization

### Execution Trace with Two Concurrent Threads

1. Thread A calls `tracingServiceRef.get()`, sees `null`
2. Thread B calls `tracingServiceRef.get()`, sees `null`
3. Thread A calls `compareAndSet(null, new TracingService())` - **succeeds**
4. Thread B calls `compareAndSet(null, new TracingService())` - **fails** (no longer null)
5. Thread B calls `tracingServiceRef.get()` - sees Thread A's instance

Result: Both threads get the same instance. Thread B's constructed object is discarded (GC'd).

---

## Deep Dive

### Volatile: What It Does and Doesn't Do

The `volatile` keyword provides **visibility** and **ordering**, but not **atomicity**.

#### Correct Use of Volatile: Simple Flags

```java
public class TracingConfig {
    private volatile boolean enabled = true;

    // Thread A (admin endpoint)
    public void disable() {
        enabled = false;  // Write goes to main memory
    }

    // Thread B (request thread)
    public boolean isEnabled() {
        return enabled;  // Read comes from main memory
    }
}
```

This is the canonical correct use: a simple flag. Both read and write are single atomic operations.

#### Incorrect Use: Compound Operations

```java
public class TracingMetrics {
    private volatile long spansEmitted = 0;

    // NOT thread-safe despite volatile
    public void recordSpan() {
        spansEmitted++;  // Read, add 1, write - three separate steps
    }
}
```

The increment compiles to: (1) read, (2) add 1, (3) write. Between steps, another thread can interfere. `volatile` makes each individual step visible but doesn't make the sequence atomic. Use `AtomicLong` instead.

### Lazy Initialization Patterns Comparison

#### Pattern 1: Holder Class Idiom (Static Singletons)

```java
public class AppConfig {
    private static class Holder {
        static final AppConfig INSTANCE = load();
    }

    public static AppConfig getInstance() {
        return Holder.INSTANCE;
    }
}
```

**When to use:**
- Static singleton with no parameters
- No need to reset (tests don't require clearing state)
- Best performance (zero synchronization overhead)

**When NOT to use:**
- Instance fields (not static)
- Needs reset capability for tests
- Initialization depends on runtime state

#### Pattern 2: AtomicReference (Instance Fields or Resettable)

```java
public class ServiceFilter {
    private final AtomicReference<TracingService> serviceRef = new AtomicReference<>();

    protected TracingService getService() {
        TracingService service = serviceRef.get();
        if (service == null) {
            serviceRef.compareAndSet(null, new TracingService());
            service = serviceRef.get();
        }
        return service;
    }
}
```

**When to use:**
- Instance fields (each object has its own lazily initialized value)
- Needs reset capability (`set(null)` for tests)
- Initialization depends on instance state

**Trade-off:**
- Multiple instances may be constructed under contention
- Only one is published, others are garbage collected
- Acceptable for stateless or cheap-to-construct objects

### Testing Support Pattern

```java
public abstract class AbstractTracingFilter {
    private final AtomicReference<TracingService> tracingServiceRef = new AtomicReference<>();

    // Production: JAX-RS runtime calls this
    protected AbstractTracingFilter() {
    }

    // Test: inject mock directly
    protected AbstractTracingFilter(TracingService tracingService) {
        this.tracingServiceRef.set(tracingService);
    }

    protected TracingService getTracingService() {
        TracingService service = tracingServiceRef.get();
        if (service == null) {
            tracingServiceRef.compareAndSet(null, new TracingService());
            service = tracingServiceRef.get();
        }
        return service;
    }
}
```

Test constructor bypasses lazy initialization, allowing mock injection for unit tests.

---

## Trade-offs and Considerations

### When to Use This

**Use `volatile` for:**
- Simple boolean flags that are read/written by different threads
- Status indicators that don't require compound operations
- Single-value state where visibility is the only concern

**Use `AtomicReference` for:**
- Lazy initialization (static or instance fields)
- Any check-then-act pattern
- When you need test reset capability
- Replacing double-checked locking patterns

**Use `AtomicInteger`/`AtomicLong` for:**
- Counters (request counts, metric tracking)
- Any increment/decrement operations
- Shared numeric state

### When NOT to Use This

**Don't use `volatile` for:**
- Compound operations (check-then-act, read-modify-write, increment)
- Multiple fields that must be updated together
- Complex state transitions requiring multiple steps

**Don't use atomic types for:**
- Multiple fields that must be updated atomically together - use `synchronized` block or `ReentrantLock`
- When the object is expensive to construct and even discarded instances are costly - use `synchronized` DCL instead
- Very frequent updates from many threads - `LongAdder` is better than `AtomicLong` for high contention

### Common Pitfalls

**Pitfall 1: Assuming `volatile` provides mutual exclusion**

```java
// WRONG: volatile reference doesn't make HashMap thread-safe
private volatile Map<String, Endpoint> cache = new HashMap<>();

public void register(String key, Endpoint endpoint) {
    cache.put(key, endpoint);  // HashMap.put() is not thread-safe
}
```

Fix: Use `ConcurrentHashMap` or synchronize access.

**Pitfall 2: Check-then-act on volatile fields**

```java
// WRONG: Race condition between check and act
private volatile TracingService service;

protected TracingService getService() {
    if (service == null) {              // Thread A sees null
        service = new TracingService(); // Thread B also sees null, both create
    }
    return service;
}
```

Fix: Use `AtomicReference` with `compareAndSet`.

**Pitfall 3: Non-atomic 64-bit writes without volatile**

```java
// WRONG: long writes are not atomic on 32-bit JVMs
private long totalBytes = 0;

public void recordBytes(int count) {
    totalBytes += count;  // Read-modify-write + non-atomic 64-bit write
}
```

Fix: Use `AtomicLong` or `volatile long` (but still won't fix the increment issue).

### Decision Table

| Scenario | Recommended Approach |
|----------|---------------------|
| Simple boolean flag | `volatile boolean` or `AtomicBoolean` |
| Lazy static singleton (non-resettable) | Holder class idiom |
| Lazy static singleton (resettable for tests) | `AtomicReference` with `compareAndSet` |
| Lazy instance field | `AtomicReference` with `compareAndSet` |
| Counter or numeric metric | `AtomicInteger` / `AtomicLong` |
| High-contention counter | `LongAdder` |
| Multiple fields updated together | `synchronized` block or `ReentrantLock` |
| Shared lookup structure | `ConcurrentHashMap`, `CopyOnWriteArrayList` |

**Guiding principle:** Make thread safety a property of the type, not a convention at the call site. When safety is embedded in the type (`AtomicReference`, `ConcurrentHashMap`, immutable records), correctness is enforced by the compiler.

---

## Key Takeaways

- **`volatile` provides visibility, not atomicity** - Use it only for simple flags, never for compound operations like check-then-act or increment
- **Atomic types make safety intrinsic** - `AtomicReference`, `AtomicInteger`, and `AtomicLong` embed thread safety in the type itself, preventing accidental misuse
- **Replace double-checked locking with `AtomicReference`** - Simpler, lock-free, and immune to forgotten `volatile` annotations
- **Use holder class idiom for static singletons** - Best performance when initialization has no parameters and doesn't need reset capability
- **Make thread safety a type property** - When correctness depends on calling conventions, a single mistake introduces a race condition
- **Test your concurrent code** - Concurrency bugs hide in production under load; use stress tests with multiple threads, not just happy-path unit tests

**Quick reference:** If you need a lock (`synchronized`) to make `volatile` work correctly, you're using the wrong tool - switch to atomic types.

---

**For code reviews:** Replace `volatile` + `synchronized` double-checked locking with `AtomicReference.compareAndSet()` - it's lock-free, self-documenting, and passes SonarQube rule java:S3077.
