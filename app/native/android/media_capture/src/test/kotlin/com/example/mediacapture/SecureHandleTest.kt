@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.example.mediacapture

import com.example.mediacapture.api.FailureCode
import com.example.mediacapture.framework.SecureOpaqueHandleGenerator
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class SecureHandleTest {
    @Test
    fun `production generator creates unique 128 bit url safe handles`() {
        val generator = SecureOpaqueHandleGenerator()
        val handles = List(1_000) { generator.nextHandle() }

        assertEquals(handles.size, handles.toSet().size)
        assertTrue(handles.all { it.length <= 128 })
        assertTrue(handles.all { Base64.getUrlDecoder().decode(it).size == 16 })
    }

    @Test
    fun `module never reuses a generated registry key`() = runTest {
        val module = TestModule(this)
        module.handles.fixed = "fixed-128-bit-equivalent-handle"
        val first = startReady(module)
        module.core.cancel(first)

        assertEquals(FailureCode.RESOURCE_IN_USE, failureCode { module.core.startSession(options()) })
        module.core.close()
    }
}
