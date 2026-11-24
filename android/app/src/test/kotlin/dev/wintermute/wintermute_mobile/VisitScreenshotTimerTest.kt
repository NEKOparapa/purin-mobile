package dev.wintermute.wintermute_mobile

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VisitScreenshotTimerTest {
    private val timer = VisitScreenshotTimer()

    private fun beforeThreshold(id: String, start: Long) {
        for (t in 0L until 600_000L step 2_000L) assertFalse(timer.due(id, start + t))
        assertFalse(timer.due(id, start + 599_999L))
    }

    @Test fun oneFramePerVisitAndNewVisitAfterSwitch() {
        beforeThreshold("a", 0)
        assertTrue(timer.due("a", 600_000))
        for (t in 602_000L..1_300_000L step 2_000L) assertFalse(timer.due("a", t))
        beforeThreshold("b", 1_302_000)
        assertTrue(timer.due("b", 1_902_000))
        beforeThreshold("a-reopened", 1_904_000)
        assertTrue(timer.due("a-reopened", 2_504_000))
    }

    @Test fun lockOrSamplingGapRestartsAnUnfinishedVisit() {
        assertFalse(timer.due("a", 0))
        assertFalse(timer.due("a", 30_000))
        beforeThreshold("a", 76_000)
        timer.reset()
        beforeThreshold("a", 676_000)
        assertTrue(timer.due("a", 1_276_000))
    }
}
