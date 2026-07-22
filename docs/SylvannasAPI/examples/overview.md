---
title: "Examples"
source: "https://docs.project-sylvanas.net/examples/"
crawled: "2026-07-14"
---

# Examples

## Overview

Welcome to the Project Sylvanas examples section! This collection of practical, real-world examples demonstrates how to leverage the Project Sylvanas APIs and libraries to build powerful plugins and automation tools for World of Warcraft. All the examples are also available on our [GitHub repository](https://github.com/bluesilvi/project-sylvanas) for you to easily clone.

Whether you're just getting started with scripting or looking to implement advanced features, these examples will guide you through the most common use cases and best practices for working with the Project Sylvanas ecosystem.

## What You'll Find Here

These examples showcase:

- **IZI SDK Integration** - Learn how to use the high-level IZI SDK to simplify your development workflow with utilities for logging, event handling, time management, and unit selection.

- **Core API Usage** - Practical demonstrations of the Core API including callbacks, game object manipulation, and spell casting.

- **Graphics & Rendering** - Examples of creating visual overlays, ESP (Extra Sensory Perception) displays, and custom UI elements using the Graphics API.

- **Event-Driven Programming** - How to respond to game events like combat state changes, buff/debuff applications, spell casts, and more using the callback system.

- **Combat Automation** - Implementing rotation helpers, target selection logic, and combat utilities using the Target Selector and other combat-focused libraries.

- **UI Development** - Creating configuration menus, control panels, and custom user interfaces with the Menu API.

## Prerequisites

Before diving into these examples, we recommend familiarizing yourself with:

- Basic Lua programming concepts (variables, functions, tables, loops)
- The Project Sylvanas Core API fundamentals
- Understanding of callbacks and event-driven programming
- The game_object class and its methods

## Example Structure

Each example includes:

- **Clear Documentation** - Detailed explanations of what the code does and why
- **Complete Code** - Full, working implementations you can use as-is or customize
- **Key Concepts** - Highlighted learning points and best practices
- **Use Cases** - Real-world scenarios where the example applies

## Example Categories

The examples are organized into two main categories to help you choose the right approach for your project:

### Legacy API

Examples in this category use **only the Core API** - the low-level functions and methods that form the foundation of Project Sylvanas. These examples are ideal for:

- **Understanding the fundamentals** - See exactly how the system works under the hood
- **Maximum control** - Fine-tune every aspect of your implementation
- **Learning the basics** - Build a solid foundation before using higher-level abstractions
- **Legacy code maintenance** - Work with existing scripts that don't use modern libraries

**Best for:** Developers who want to understand the core mechanisms, need precise control, or are maintaining existing code.

### IZI SDK

Examples in this category leverage the **IZI SDK** - a high-level toolkit that provides cleaner, more intuitive APIs and powerful utilities. These examples are ideal for:

- **Faster development** - Write less boilerplate code and focus on features
- **Modern best practices** - Use event-driven patterns, helpers, and smart abstractions
- **Complex features** - Build advanced functionality with less effort
- **Production plugins** - Create professional-grade solutions quickly

**Best for:** Developers building new plugins, implementing complex features, or who prefer working with modern, high-level APIs.

## Recommended Learning Path

If you're new to Project Sylvanas development, we **strongly recommend starting with the IZI SDK examples**. Here's why:

- **Easier to learn** - Clean, intuitive APIs that abstract away complexity
- **Fewer mistakes** - Built-in helpers prevent common errors and edge cases
- **Better documentation** - Modern examples with clear patterns and best practices
- **Faster results** - Get your plugin working quickly without getting bogged down in low-level details

Once you're comfortable building with the IZI SDK, you can explore Legacy API examples to:

- Understand how things work under the hood
- Debug complex issues more effectively
- Optimize performance-critical sections
- Maintain or modify existing legacy code

**You can mix and match** - Use the IZI SDK for most of your code while dropping down to the Core API when you need fine-grained control. The IZI SDK is built on top of the Core API, so they work seamlessly together.

## Contributing

Have a useful example you'd like to share? Found a better way to implement something? We welcome contributions! Reach out to us on discord to discuss adding your example.

Happy coding!
