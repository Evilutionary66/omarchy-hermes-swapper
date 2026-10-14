const MODELS = {
    STRATA: {
        name: "Strata (Qwen)",
        endpoint: "http://localhost:8080/v1", // Replace with your Strata port
        model_id: "qwen3.8-flash-next-iq3_xxs"
    },
    LM_STUDIO: {
        name: "LM Studio (Gemma 4)",
        endpoint: "http://localhost:1234/v1", // Replace with your LM Studio port
        model_id: "google/gemma-4-12b-qat"
    }
};

export function swapModel(isStrata) {
    const config = isStrata ? MODELS.STRATA : MODELS.LM_STUDIO;
    
    // We use the Hermes host request to update the active session configuration
    // This effectively hot-swaps the provider/model for the active Hermes instance
    host.request("config.set_model", {
        name: config.model_id,
        endpoint: config.endpoint,
        provider: "local"
    }).then(res => {
        console.log(`Switched to ${config.name}`);
        // Optional: Trigger a UI refresh or notification
        host.notify({ kind: "success", message: `Switched to ${config.name}` });
    }).catch(err => {
        console.error("Failed to swap model:", err);
    });
}