package dev.projectuai.relay.protocol

import kotlinx.serialization.Serializable

@Serializable
data class CancelledResponse(val cancelled: Boolean)
