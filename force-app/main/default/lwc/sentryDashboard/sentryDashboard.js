import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { publish, MessageContext } from 'lightning/messageService';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardData from '@salesforce/apex/SentryMonitoringController.getDashboardData';
import runElfRetrieval from '@salesforce/apex/SentryMonitoringController.runElfRetrieval';
import DASHBOARD_UPDATES from '@salesforce/messageChannel/SentryDashboardUpdates__c';

export default class SentryDashboard extends LightningElement {
    wiredDashboard;
    subscription;
    streamingStatus = 'Not connected';
    events = [];
    incidents = [];
    retrievalJobs = [];
    queueTelemetry = [];
    connectorDeliveries = [];
    metrics = [];
    timeline = [];
    heatmap = [];
    featureLicenses = [];
    detectionRules = [];

    @wire(MessageContext)
    messageContext;

    @wire(getDashboardData)
    wiredData(value) {
        this.wiredDashboard = value;
        const { data, error } = value;
        if (data) {
            this.events = data.recentEvents || [];
            this.incidents = data.recentIncidents || [];
            this.retrievalJobs = data.retrievalJobs || [];
            this.queueTelemetry = data.queueTelemetry || [];
            this.connectorDeliveries = data.connectorDeliveries || [];
            this.metrics = data.metrics || [];
            this.timeline = data.timeline || [];
            this.heatmap = data.heatmap || [];
            this.featureLicenses = data.featureLicenses || [];
            this.detectionRules = data.detectionRules || [];
        } else if (error) {
            this.showToast('Error loading dashboard', error.body?.message || 'Unknown error', 'error');
        }
    }

    connectedCallback() {
        this.subscribeToEvents();
        onError(() => {
            this.streamingStatus = 'Streaming error';
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                this.subscription = null;
            });
        }
    }

    async handleElfRetrieval() {
        try {
            await runElfRetrieval();
            this.showToast('ELF retrieval queued', 'Latest Event Log File retrieval job was executed.', 'success');
            await this.refreshDashboard();
        } catch (error) {
            this.showToast('ELF retrieval failed', error.body?.message || 'Unknown error', 'error');
        }
    }

    async refreshDashboard() {
        if (this.wiredDashboard) {
            await refreshApex(this.wiredDashboard);
        }
        publish(this.messageContext, DASHBOARD_UPDATES, {
            payload: {
                type: 'refresh',
                timestamp: Date.now()
            }
        });
    }

    subscribeToEvents() {
        const channel = '/event/Sentry_Event_Stream__e';
        subscribe(channel, -1, async () => {
            this.streamingStatus = 'Connected';
            await this.refreshDashboard();
        }).then((response) => {
            this.subscription = response;
            this.streamingStatus = 'Connected';
        }).catch(() => {
            this.streamingStatus = 'Channel unavailable';
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
