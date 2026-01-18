package telemetry

// This file demonstrates how to add a log bridge to capture ALL stdout/stderr logs
// and send them via OTLP. Uncomment and integrate into logger.go if needed.

/*
import (
	"log"
	"go.opentelemetry.io/contrib/bridges/stdlib"
	"go.opentelemetry.io/otel/log/global"
)

// enableLogBridge bridges standard Go log library to OpenTelemetry
// This captures ALL log.Printf() calls and sends them via OTLP
func enableLogBridge() error {
	// Create bridge from standard library log to OTel
	bridge := stdlib.NewBridge()

	// Set the logger provider (must be initialized first)
	bridge.SetLoggerProvider(global.LoggerProvider())

	// Now all log.Printf() calls will also go via OTLP
	log.Printf("[INFO] Log bridge enabled - all stdout/stderr logs will be sent via OTLP")

	return nil
}

// Usage in InitializeLogger():
// 1. Initialize OTLP logger first (as currently done)
// 2. Then enable log bridge:
//    if useOTLP {
//        if err := enableLogBridge(); err != nil {
//            log.Printf("[WARN] Failed to enable log bridge: %v", err)
//        }
//    }
*/
