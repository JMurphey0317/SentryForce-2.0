import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import simulateDetection from '@salesforce/apex/SentryMonitoringController.simulateDetection';

export default class SentryRuleSimulator extends LightningElement {
    source = 'EventMonitoring';
    eventType = 'ReportExport';
    actorId = '005000000000001';
    attributesJson = '{"bulkDownload":true,"exportSizeMb":650}';
    result;

    get factorText() {
        return this.result?.factors?.join(', ') || '';
    }

    handleSourceChange(event) {
        this.source = event.target.value;
    }

    handleEventTypeChange(event) {
        this.eventType = event.target.value;
    }

    handleActorChange(event) {
        this.actorId = event.target.value;
    }

    handleAttributesChange(event) {
        this.attributesJson = event.target.value;
    }

    async runSimulation() {
        try {
            this.result = await simulateDetection({
                source: this.source,
                eventType: this.eventType,
                actorId: this.actorId,
                attributesJson: this.attributesJson
            });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Simulation failed',
                    message: error.body?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }
}
