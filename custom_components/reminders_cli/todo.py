"""Todo platform for Reminders CLI integration."""
from __future__ import annotations

import logging
from datetime import datetime

from homeassistant.components.todo import (
    TodoItem,
    TodoItemStatus,
    TodoListEntity,
    TodoListEntityFeature,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity
from homeassistant.util import slugify

from . import RemindersDataUpdateCoordinator
from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up the Reminders CLI todo platform."""
    coordinator: RemindersDataUpdateCoordinator = hass.data[DOMAIN][entry.entry_id]

    # Create a todo entity for each reminder list
    entities = [
        RemindersTodoListEntity(coordinator, list_name)
        for list_name in coordinator.lists_data.keys()
    ]

    async_add_entities(entities)


class RemindersTodoListEntity(CoordinatorEntity[RemindersDataUpdateCoordinator], TodoListEntity):
    """A To-do List representation of a Reminders list."""

    _attr_has_entity_name = True
    _attr_supported_features = (
        TodoListEntityFeature.CREATE_TODO_ITEM
        | TodoListEntityFeature.DELETE_TODO_ITEM
        | TodoListEntityFeature.UPDATE_TODO_ITEM
        | TodoListEntityFeature.SET_DUE_DATETIME_ON_ITEM
        | TodoListEntityFeature.SET_DESCRIPTION_ON_ITEM
    )

    def __init__(
        self,
        coordinator: RemindersDataUpdateCoordinator,
        list_name: str,
    ) -> None:
        """Initialize the todo list entity."""
        super().__init__(coordinator)
        self.list_name = list_name
        self._attr_unique_id = f"{coordinator.entry.entry_id}_{slugify(list_name)}"
        self._attr_name = list_name

    @property
    def device_info(self):
        """Return device info for grouping entities."""
        return {
            "identifiers": {(DOMAIN, self.coordinator.entry.entry_id)},
            "name": "Reminders CLI",
            "manufacturer": "Apple",
            "model": "macOS Reminders",
            "entry_type": "service",
        }

    @property
    def available(self) -> bool:
        """Return True if entity is available."""
        return self.coordinator.last_update_success

    @property
    def todo_items(self) -> list[TodoItem] | None:
        """Return the todo items."""
        reminders = self.coordinator.lists_data.get(self.list_name, [])

        return [
            TodoItem(
                uid=reminder["id"],
                summary=reminder.get("title", ""),
                status=TodoItemStatus.COMPLETED
                if reminder.get("isCompleted", False)
                else TodoItemStatus.NEEDS_ACTION,
                due=self._parse_due_date(reminder.get("dueDate")),
                description=reminder.get("notes"),
            )
            for reminder in reminders
        ]

    def _parse_due_date(self, due_date_str: str | None) -> datetime | None:
        """Parse due date string to datetime."""
        if not due_date_str:
            return None
        try:
            return datetime.fromisoformat(due_date_str.replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            _LOGGER.warning("Failed to parse due date: %s", due_date_str)
            return None

    async def async_create_todo_item(self, item: TodoItem) -> None:
        """Create a new todo item."""
        try:
            await self.coordinator.api.create_reminder(
                list_name=self.list_name,
                title=item.summary,
                notes=item.description,
                due_date=item.due,
            )
            await self.coordinator.async_refresh_list(self.list_name)
        except Exception as err:
            raise HomeAssistantError(f"Failed to create reminder: {err}") from err

    async def async_update_todo_item(self, item: TodoItem) -> None:
        """Update a todo item."""
        try:
            reminder_id = self._extract_reminder_id(item.uid)
            reminders = self.coordinator.lists_data.get(self.list_name, [])
            current_reminder = next(
                (r for r in reminders if r["id"] == reminder_id), None
            )

            if not current_reminder:
                raise HomeAssistantError(
                    f"Reminder {item.uid} not found in list {self.list_name}"
                )

            # Check if completion status changed
            is_completed = item.status == TodoItemStatus.COMPLETED
            was_completed = current_reminder.get("isCompleted", False)

            # Check if non-status fields changed
            current_due = self._parse_due_date(current_reminder.get("dueDate"))
            title_changed = item.summary != current_reminder.get("title")
            notes_changed = item.description != current_reminder.get("notes")
            due_changed = item.due != current_due

            # If only status changed, use complete/uncomplete endpoints
            if is_completed != was_completed and not (title_changed or notes_changed or due_changed):
                if is_completed:
                    await self.coordinator.api.complete_reminder(
                        self.list_name, reminder_id
                    )
                else:
                    await self.coordinator.api.uncomplete_reminder(
                        self.list_name, reminder_id
                    )
            else:
                # Update all fields (including status via isCompleted in the update)
                # Note: The update endpoint doesn't support isCompleted, so we still need
                # to call complete/uncomplete if status changed
                if is_completed != was_completed:
                    if is_completed:
                        await self.coordinator.api.complete_reminder(
                            self.list_name, reminder_id
                        )
                    else:
                        await self.coordinator.api.uncomplete_reminder(
                            self.list_name, reminder_id
                        )

                # Only call update if non-status fields changed
                if title_changed or notes_changed or due_changed:
                    await self.coordinator.api.update_reminder(
                        list_name=self.list_name,
                        reminder_id=reminder_id,
                        title=item.summary if title_changed else None,
                        notes=item.description if notes_changed else None,
                        due_date=item.due if due_changed else None,
                    )

            await self.coordinator.async_refresh_list(self.list_name)
        except Exception as err:
            raise HomeAssistantError(f"Failed to update reminder: {err}") from err

    async def async_delete_todo_items(self, uids: list[str]) -> None:
        """Delete todo items."""
        try:
            for uid in uids:
                reminder_id = self._extract_reminder_id(uid)
                await self.coordinator.api.delete_reminder(self.list_name, reminder_id)

            await self.coordinator.async_refresh_list(self.list_name)
        except Exception as err:
            raise HomeAssistantError(f"Failed to delete reminders: {err}") from err

    def _extract_reminder_id(self, uid: str) -> str:
        """Extract reminder ID from UID."""
        # The API returns IDs in the format "x-apple-reminder://UUID"
        # We need just the UUID part
        if uid.startswith("x-apple-reminder://"):
            return uid.replace("x-apple-reminder://", "")
        return uid
