import { LightningElement, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/SentryMonitoringController.getDashboardData';
import runElfRetrieval from '@salesforce/apex/SentryMonitoringController.runElfRetrieval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SentryForceConsole extends LightningElement {
    events = [];
    alerts = [];

    @wire(getDashboardData)
    wiredData({ error, data }) {
        if (data) {
            this.events = data.recentEvents || [];
            this.alerts = data.recentAlerts || [];
        } else if (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading dashboard',
                    message: error.body?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }

    async runElfRetrieval() {
        try {
            await runElfRetrieval();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'ELF retrieval queued',
                    message: 'Latest Event Log File retrieval job was executed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'ELF retrieval failed',
                    message: error.body?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        }
    }
}
