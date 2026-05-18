import { LightningElement, api } from 'lwc';

export default class SentryIncidentPanel extends LightningElement {
    @api incidents = [];
    @api deliveries = [];
}
