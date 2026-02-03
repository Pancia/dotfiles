"""Unit tests for JobEventBus."""

import asyncio
import sys
from pathlib import Path

import pytest

# Add services to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "services" / "youtube-transcribe"))

from server import JobEventBus


class TestPublish:
    """Tests for publishing events."""

    @pytest.mark.asyncio
    async def test_publish_adds_to_history(self):
        """Published events should be added to event history."""
        bus = JobEventBus(job_id="test123")

        await bus.publish({"event": "started", "data": {"title": "Test Video"}})

        assert len(bus.event_history) == 1
        assert bus.event_history[0]["event"] == "started"
        assert bus.event_history[0]["data"]["title"] == "Test Video"
        assert "_seq" in bus.event_history[0]

    @pytest.mark.asyncio
    async def test_publish_broadcasts_to_subscribers(self):
        """Published events should be sent to all subscribers."""
        bus = JobEventBus(job_id="test123")
        queue = await bus.subscribe("subscriber1")

        await bus.publish({"event": "progress", "data": {"percent": 50}})

        event = queue.get_nowait()
        assert event["event"] == "progress"
        assert event["data"]["percent"] == 50

    @pytest.mark.asyncio
    async def test_publish_to_multiple_subscribers(self):
        """Events should be broadcast to all subscribers."""
        bus = JobEventBus(job_id="test123")
        queue1 = await bus.subscribe("subscriber1")
        queue2 = await bus.subscribe("subscriber2")

        await bus.publish({"event": "test"})

        event1 = queue1.get_nowait()
        event2 = queue2.get_nowait()
        assert event1["event"] == "test"
        assert event2["event"] == "test"

    @pytest.mark.asyncio
    async def test_sequence_numbers_increment(self):
        """Each published event should have an incrementing sequence number."""
        bus = JobEventBus(job_id="test123")

        await bus.publish({"event": "first"})
        await bus.publish({"event": "second"})
        await bus.publish({"event": "third"})

        assert bus.event_history[0]["_seq"] == 0
        assert bus.event_history[1]["_seq"] == 1
        assert bus.event_history[2]["_seq"] == 2


class TestHistoryRingBuffer:
    """Tests for event history ring buffer."""

    @pytest.mark.asyncio
    async def test_history_ring_buffer_limit(self):
        """History should not exceed max_history size."""
        bus = JobEventBus(job_id="test123", max_history=5)

        for i in range(10):
            await bus.publish({"event": f"event_{i}"})

        assert len(bus.event_history) == 5
        # Should keep the most recent events
        assert bus.event_history[0]["event"] == "event_5"
        assert bus.event_history[-1]["event"] == "event_9"

    @pytest.mark.asyncio
    async def test_get_history_since_filters_by_seq(self):
        """get_history_since should return only events after the given sequence."""
        bus = JobEventBus(job_id="test123")

        for i in range(5):
            await bus.publish({"event": f"event_{i}"})

        history = await bus.get_history_since(seq=3)

        assert len(history) == 2
        assert history[0]["event"] == "event_3"
        assert history[1]["event"] == "event_4"

    @pytest.mark.asyncio
    async def test_get_history_since_zero_returns_all(self):
        """get_history_since(0) should return all events."""
        bus = JobEventBus(job_id="test123")

        for i in range(3):
            await bus.publish({"event": f"event_{i}"})

        history = await bus.get_history_since(seq=0)

        assert len(history) == 3


class TestComplete:
    """Tests for job completion."""

    @pytest.mark.asyncio
    async def test_complete_sets_is_complete(self):
        """complete() should set is_complete flag."""
        bus = JobEventBus(job_id="test123")

        await bus.complete()

        assert bus.is_complete is True

    @pytest.mark.asyncio
    async def test_complete_sends_sentinel(self):
        """complete() should send None sentinel to all subscribers."""
        bus = JobEventBus(job_id="test123")
        queue = await bus.subscribe("subscriber1")

        await bus.complete()

        sentinel = queue.get_nowait()
        assert sentinel is None

    @pytest.mark.asyncio
    async def test_complete_event_captured_as_final_result(self):
        """Complete events should be captured as final_result."""
        bus = JobEventBus(job_id="test123")

        await bus.publish({
            "event": "complete",
            "data": {"transcript": "Hello world", "saved_to": "/tmp/test.txt"}
        })

        assert bus.final_result is not None
        assert bus.final_result["transcript"] == "Hello world"


class TestSubscription:
    """Tests for subscription management."""

    @pytest.mark.asyncio
    async def test_subscribe_creates_queue(self):
        """subscribe() should return an asyncio.Queue."""
        bus = JobEventBus(job_id="test123")

        queue = await bus.subscribe("subscriber1")

        assert isinstance(queue, asyncio.Queue)
        assert "subscriber1" in bus.subscribers

    @pytest.mark.asyncio
    async def test_unsubscribe_removes_subscriber(self):
        """unsubscribe() should remove the subscriber."""
        bus = JobEventBus(job_id="test123")
        await bus.subscribe("subscriber1")

        await bus.unsubscribe("subscriber1")

        assert "subscriber1" not in bus.subscribers

    @pytest.mark.asyncio
    async def test_unsubscribe_nonexistent_subscriber(self):
        """unsubscribe() should not error for nonexistent subscriber."""
        bus = JobEventBus(job_id="test123")

        # Should not raise
        await bus.unsubscribe("nonexistent")

    @pytest.mark.asyncio
    async def test_full_queue_skips_event(self):
        """When a subscriber's queue is full, events should be skipped."""
        bus = JobEventBus(job_id="test123")
        queue = await bus.subscribe("subscriber1")

        # Fill up the queue (maxsize=100)
        for i in range(100):
            await bus.publish({"event": f"event_{i}"})

        # This should not raise even though queue is full
        await bus.publish({"event": "overflow"})

        # Queue should still be at max capacity
        assert queue.qsize() == 100
