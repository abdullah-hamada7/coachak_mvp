"""Shared Pydantic schemas for Coachak API."""

from datetime import date, datetime
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class Sex(str, Enum):
    male = "male"
    female = "female"
    other = "other"


class ActivityLevel(str, Enum):
    sedentary = "sedentary"
    light = "light"
    moderate = "moderate"
    active = "active"
    very_active = "very_active"


class GoalType(str, Enum):
    fat_loss = "fat_loss"
    hypertrophy = "hypertrophy"
    strength = "strength"
    mobility = "mobility"
    general_fitness = "general_fitness"


class ExperienceLevel(str, Enum):
    beginner = "beginner"
    intermediate = "intermediate"
    advanced = "advanced"


class DietaryPreference(str, Enum):
    omnivore = "omnivore"
    vegetarian = "vegetarian"
    vegan = "vegan"
    pescatarian = "pescatarian"


# Auth
class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    display_name: str = Field(min_length=1, max_length=100)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


# Profile
class UserProfileUpdate(BaseModel):
    display_name: str | None = None
    age: int | None = Field(default=None, ge=13, le=100)
    sex: Sex | None = None
    weight_kg: float | None = Field(default=None, gt=0)
    height_cm: float | None = Field(default=None, gt=0)
    activity_level: ActivityLevel | None = None
    experience_level: ExperienceLevel | None = None
    injuries: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    dietary_preference: DietaryPreference | None = None
    workout_days_per_week: int | None = Field(default=None, ge=1, le=7)
    primary_goal: GoalType | None = None


class UserProfileResponse(BaseModel):
    id: UUID
    email: str
    display_name: str
    age: int | None = None
    sex: Sex | None = None
    weight_kg: float | None = None
    height_cm: float | None = None
    activity_level: ActivityLevel | None = None
    experience_level: ExperienceLevel | None = None
    injuries: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    dietary_preference: DietaryPreference | None = None
    workout_days_per_week: int | None = None
    primary_goal: GoalType | None = None
    onboarding_complete: bool = False
    created_at: datetime


# Workout plans
class ExerciseSet(BaseModel):
    reps: int | None = None
    weight_kg: float | None = None
    duration_seconds: int | None = None
    rpe: float | None = Field(default=None, ge=1, le=10)


class PlannedExercise(BaseModel):
    name: str
    muscle_groups: list[str] = Field(default_factory=list)
    sets: list[ExerciseSet]
    notes: str | None = None
    contraindications: list[str] = Field(default_factory=list)


class WorkoutSessionPlan(BaseModel):
    day_label: str
    week_number: int
    focus: str
    exercises: list[PlannedExercise]
    estimated_minutes: int = 45


class WorkoutPlan(BaseModel):
    title: str
    weeks: int = 4
    sessions: list[WorkoutSessionPlan]
    progression_notes: str | None = None


class WorkoutPlanResponse(BaseModel):
    id: UUID
    plan: WorkoutPlan
    is_active: bool
    created_at: datetime


# Nutrition plans
class MacroTargets(BaseModel):
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float | None = None


class MealItem(BaseModel):
    name: str
    portion: str
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float


class MealPlan(BaseModel):
    meal_type: str
    items: list[MealItem]
    total_calories: int


class DailyMealPlan(BaseModel):
    day_label: str
    meals: list[MealPlan]


class NutritionPlan(BaseModel):
    title: str
    tdee: int
    target_macros: MacroTargets
    daily_plans: list[DailyMealPlan]
    hydration_liters: float = 2.5
    notes: str | None = None


class NutritionPlanResponse(BaseModel):
    id: UUID
    plan: NutritionPlan
    is_active: bool
    created_at: datetime


# Food vision
class FoodItemAnalysis(BaseModel):
    name: str
    portion_estimate: str
    confidence: float = Field(ge=0, le=1)
    usda_fdc_id: int | None = None
    calories: float | None = None
    protein_g: float | None = None
    carbs_g: float | None = None
    fat_g: float | None = None


class FoodAnalysis(BaseModel):
    items: list[FoodItemAnalysis]
    total_calories: float | None = None
    total_protein_g: float | None = None
    total_carbs_g: float | None = None
    total_fat_g: float | None = None
    notes: str | None = None


class FoodLogCreate(BaseModel):
    items: list[FoodItemAnalysis]
    meal_type: str = "other"
    logged_at: datetime | None = None


# Form CV
class FormCorrectionEvent(BaseModel):
    timestamp_ms: int
    cue: str
    severity: str = "info"


class FormSessionUpload(BaseModel):
    exercise: str
    rep_count: int
    duration_seconds: int
    corrections: list[FormCorrectionEvent] = Field(default_factory=list)
    avg_rom_score: float | None = Field(default=None, ge=0, le=1)


# Chat
class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    thread_id: str | None = None


class ChatStreamEvent(BaseModel):
    event: str
    data: dict[str, Any]


# Gamification
class Badge(BaseModel):
    id: str
    name: str
    description: str
    earned_at: datetime | None = None


class Habit(BaseModel):
    id: UUID
    name: str
    target_per_day: int = 1
    checked_today: bool = False
    streak: int = 0


class HabitCreate(BaseModel):
    name: str
    target_per_day: int = 1


class GamificationState(BaseModel):
    total_xp: int
    level: int
    workout_streak: int
    logging_streak: int
    badges: list[Badge]
    habits: list[Habit]


class ProgressSummary(BaseModel):
    workouts_completed: int
    total_reps_tracked: int
    avg_daily_calories: float | None = None
    macro_adherence_pct: float | None = None
    form_sessions: int
    xp: int
    level: int


# Safety validation
class SafetyValidationResult(BaseModel):
    passed: bool
    issues: list[str] = Field(default_factory=list)
    suggestions: list[str] = Field(default_factory=list)


# Workout logs
class WorkoutLogCreate(BaseModel):
    session_label: str
    exercises_completed: list[str] = Field(default_factory=list)
    duration_minutes: int | None = None
    notes: str | None = None
    completed_at: datetime | None = None
