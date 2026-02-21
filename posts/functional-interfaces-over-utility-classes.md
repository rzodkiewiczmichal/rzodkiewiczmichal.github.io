# Stop Writing Java Utility Classes the Old Way: Use Functional Interfaces Instead

**Date:** 2026-02-21
**Tags:** #java #best-practices #functional-programming #ddd

---

## Introduction

Static utility classes spread business logic across your codebase and make it hard to test. Functional interfaces let you express domain rules as composable, testable functions that belong in your domain model.

---

## The Problem

Business rules hidden in static utility classes:

```java
public class OrderValidationUtils {
    public static boolean isValidForProcessing(Order order) {
        return order.getTotalAmount() > 0
            && order.getItems().size() > 0
            && order.getCustomer() != null;
    }
}

// Usage scattered across the codebase
if (OrderValidationUtils.isValidForProcessing(order)) {
    processOrder(order);
}
```

**Problems:**
- Business rules hidden in utility class, not in domain
- Hard to test (static methods)
- Can't compose rules
- Not reusable or injectable

---

## The Solution: Domain Rules as Functions

Express business rules using `Predicate<T>` in your domain model:

```java
public class Order {
    private final List<OrderItem> items;
    private final Money totalAmount;
    private final Customer customer;

    // Domain rules as predicates - business logic in the domain!
    public static final Predicate<Order> hasItems =
        order -> !order.items.isEmpty();

    public static final Predicate<Order> hasPositiveAmount =
        order -> order.totalAmount.isPositive();

    public static final Predicate<Order> hasCustomer =
        order -> order.customer != null;

    // Compose rules
    public static final Predicate<Order> canBeProcessed =
        hasItems.and(hasPositiveAmount).and(hasCustomer);

    public boolean isReadyForProcessing() {
        return canBeProcessed.test(this);
    }
}

// Usage
if (order.isReadyForProcessing()) {
    processOrder(order);
}
```

**Advantages:**
- Business rules live in the domain model (DDD principle)
- Composable - combine rules with `.and()`, `.or()`
- Testable - easy to unit test each rule
- Explicit - rules are named and visible
- Reusable - inject into services

---

## Real-World Example: User Registration

**Before (Utility Class):**

```java
public class UserValidationUtils {
    public static boolean canRegister(User user) {
        return user.getAge() >= 18
            && user.getEmail() != null
            && user.hasAcceptedTerms();
    }
}
```

**After (Domain Model):**

```java
public class User {
    private final int age;
    private final Email email;
    private final boolean termsAccepted;

    // Business rules in domain - DDD style
    public static final Predicate<User> isAdult =
        user -> user.age >= 18;

    public static final Predicate<User> hasEmail =
        user -> user.email != null;

    public static final Predicate<User> acceptedTerms =
        user -> user.termsAccepted;

    // Compose business rules
    public static final Predicate<User> canRegister =
        isAdult.and(hasEmail).and(acceptedTerms);

    public boolean isEligibleForRegistration() {
        return canRegister.test(this);
    }
}

// In service - inject for testing
public class RegistrationService {
    private final Predicate<User> registrationPolicy;

    public RegistrationService(Predicate<User> policy) {
        this.registrationPolicy = policy;
    }

    public void register(User user) {
        if (registrationPolicy.test(user)) {
            // proceed with registration
        }
    }
}

// Production: use domain rules
new RegistrationService(User.canRegister);

// Testing: inject test policy
new RegistrationService(user -> true);
```

---

## DDD Connection

In Domain-Driven Design, business rules belong in the domain model, not in utility classes:

- **Predicates = Specifications** - Functional interfaces are lightweight specifications
- **Domain rules are explicit** - Named predicates make business logic visible
- **Composable invariants** - Combine rules to express complex domain constraints
- **Testable in isolation** - Each rule is a pure function you can test independently

---

## Key Takeaways

- Business rules belong in the domain model, not utility classes
- Use `Predicate<T>` to express domain rules as composable functions
- Combine rules with `.and()`, `.or()` for complex validations
- Inject predicates into services for testability

**For code reviews:** When you see static validation utils, ask: "Should this be a domain rule expressed as a Predicate?"
