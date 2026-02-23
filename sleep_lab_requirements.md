# Sleep Lab — Personal Sleep Experimentation & Analysis App

## 1. Vision

Sleep Lab is a **local-first sleep experimentation and visualization app** designed to help users deeply understand their sleep patterns through direct graph comparison, physiological data correlation, and personalized scoring.

Unlike traditional sleep apps that provide shallow analytics or generic insights, Sleep Lab functions as a **personal sleep laboratory**, allowing users to:

- Compare sleep structure across multiple days
- Visualize sleep stage cycles and transitions
- Correlate behaviors (caffeine, workouts, dinner timing) with sleep structure
- Build and refine their own sleep score algorithm
- Run personal experiments and see real physiological effects

This app prioritizes **visual evidence over abstract conclusions.**

---

## 2. Core Principles

### 2.1 Local-first architecture
- All data stored locally
- No cloud storage
- No external servers
- No login required
- Full privacy

### 2.2 Evidence-driven visualization
- Graphs are primary interface
- No oversimplified conclusions
- User interprets patterns directly

### 2.3 Experimentation-focused
- User runs experiments
- Compares outcomes visually
- Learns personal sleep drivers

### 2.4 High fidelity physiological analysis
- Full sleep stage structure visualization
- Heart rate and HRV integration
- Temporal alignment and comparison

---

## 3. Target User Persona

Primary user:

- Athlete or fitness enthusiast
- Quantified-self enthusiast
- Engineer / technical thinker
- Optimization-focused individual
- Apple Watch user

---

## 4. Core Features

### HealthKit Integration
Pull:
- Sleep stages
- Heart rate
- HRV
- Respiratory rate
- Workouts

### Timeline View
- Scrollable days
- Sleep cards
- Mini graphs
- Multi-select

### Comparison Engine
- Compare 2–5 days
- Overlay hypnograms
- Average graphs
- Aligned graphs

### Behavioral Tagging
Log:
- caffeine
- workout
- dinner
- stress

### Custom Sleep Score
Personal scoring model using physiological data.

---

## 5. User Flow

First Launch:
1. Request HealthKit permission
2. Import data
3. Show timeline

Normal Flow:
1. Select days
2. Compare graphs
3. Analyze differences

---

## 6. Screens

- Health Permission Screen
- Timeline Screen
- Comparison Screen
- Detail Screen

---

## 7. Technical Architecture

Platform:
- iOS

Stack:
- SwiftUI
- HealthKit
- Swift Charts
- CoreData

Architecture:
- MVVM

---

## 8. Privacy

Fully local.

No cloud.

---

## 9. Development Phases

1. HealthKit integration
2. Timeline UI
3. Comparison UI
4. Tagging
5. Custom scoring
6. Pattern detection

---

## 10. Summary

Sleep Lab transforms sleep tracking into sleep experimentation.
