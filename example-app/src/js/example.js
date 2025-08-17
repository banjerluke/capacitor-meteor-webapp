import { CapacitorMeteorWebApp } from '@strummachine/capacitor-meteor-webapp';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    CapacitorMeteorWebApp.echo({ value: inputValue })
}
