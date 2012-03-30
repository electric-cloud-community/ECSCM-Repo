
// Reports.java --
//
// Reports.java is part of ElectricCommander.
//
// Copyright (c) 2005-2010 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.HashMap;
import java.util.Map;

import com.google.gwt.event.dom.client.ClickEvent;
import com.google.gwt.event.dom.client.ClickHandler;
import com.google.gwt.http.client.Request;
import com.google.gwt.http.client.RequestCallback;
import com.google.gwt.http.client.RequestException;
import com.google.gwt.http.client.Response;
import com.google.gwt.user.client.Window.Location;
import com.google.gwt.user.client.ui.Anchor;
import com.google.gwt.user.client.ui.Button;
import com.google.gwt.user.client.ui.DecoratorPanel;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.domain.Property;
import com.electriccloud.commander.gwt.client.domain.PropertySheet;
import com.electriccloud.commander.gwt.client.protocol.xml.RequestSerializer;
import com.electriccloud.commander.gwt.client.requests.CgiRequestProxy;
import com.electriccloud.commander.gwt.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.gwt.client.requests.RunProcedureRequest;
import com.electriccloud.commander.gwt.client.responses.CommanderError;
import com.electriccloud.commander.gwt.client.responses.PropertySheetCallback;
import com.electriccloud.commander.gwt.client.responses.RunProcedureResponse;
import com.electriccloud.commander.gwt.client.responses.RunProcedureResponseCallback;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.SimpleErrorBox;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

import static com.electriccloud.commander.gwt.client.ComponentBaseFactory.getPluginName;
import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createUrl;

/**
 */
public class Reports
    extends ComponentBase
{

    //~ Instance fields --------------------------------------------------------

    /** Renders the component. */
    private DecoratorPanel m_rootPanel;
    private FormTable      formTable;
    private FormTable      formTableUpdated;
    private FormTable      formTableCreated;

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {
        m_rootPanel = new DecoratorPanel();

        VerticalPanel vPanel = new VerticalPanel();

        vPanel.setBorderWidth(0);

        final String        jobId      = getGetParameter("jobId");
        CommanderUrlBuilder urlBuilder = createUrl("jobDetails.php")
                .setParameter("jobId", jobId);

        vPanel.add(new Anchor("Job: " + jobId, urlBuilder.buildString()));

        HTML htmlH1 = new HTML("<h1>Perforce Changelog</h1>");

        vPanel.add(htmlH1);
        
        HTML htmlLabel = new HTML(
                "<p><b>Perforce changelogs associated with the ElectricCommander job:</b></p>");

        vPanel.add(htmlLabel);
        formTable = getUIFactory().createFormTable();
        callback("ecscm_changeLogs", formTable);
        vPanel.add(formTable.getWidget());
        
        m_rootPanel.add(vPanel);

        return m_rootPanel;
    }

    private void callback(
            final String    propertyName,
            final FormTable formTable)
    {
        final String jobId = getGetParameter("jobId");

        if (getLog().isDebugEnabled()) {
            getLog().debug("this is getGetParameter for jobId: "
                    + getGetParameter("jobId"));
            getLog().debug("this is jobId: " + jobId);
        }

        GetPropertiesRequest req = getRequestFactory()
                .createGetPropertiesRequest();

        
        req.setPath("/jobs/" + jobId + "/" + propertyName);

        if (getLog().isDebugEnabled()) {
            getLog().debug(
                "p4 Reports doInit: setting up getProperties command request");
        }

        req.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {

                    parseResponse(response, formTable);
                    
                }

                @Override public void handleError(CommanderError error)
                {

                    if (getLog().isDebugEnabled()) {
                        getLog().debug("Error trying to access property");
                    }

                    formTable.addRow("0", new Label("No changelogs Found"));
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("p4 Reports doInit: Issuing Commander request: "
                    + RequestSerializer.serialize(req));
        }

        doRequest(req);
    }

   
    private void parseResponse(
            PropertySheet response,
            FormTable     form)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug("getProperties request returned "
                    + String.valueOf(response.getProperties()
                                             .size()) + " properties");
        }

        for (Property p : response.getProperties()
                                  .values()) {
            
            HTML htmlH1 = new HTML("<h3>"+p.getName()+"</h3> <pre>"+ p.getValue() +"</pre>");
            form.addRow("0", htmlH1);

            if (getLog().isDebugEnabled()) {
                getLog().debug("  propertyName="
                        + p.getName()
                        + ", value=" + p.getValue());
            }
        }
    }


    private void waitForJob(final String jobId)
    {
        CgiRequestProxy     cgiRequestProxy = new CgiRequestProxy(
                getPluginName(), "monitorJob.cgi");
        Map<String, String> cgiParams       = new HashMap<String, String>();

        cgiParams.put("jobId", jobId);

        // Pass debug flag to CGI, which will use it to determine whether to
        // clean up a successful job
        if ("1".equals(getGetParameter("debug"))) {
            cgiParams.put("debug", "1");
        }

        try {
            cgiRequestProxy.issueGetRequest(cgiParams, new RequestCallback() {
                    @Override public void onError(
                            Request   request,
                            Throwable exception)
                    {

                        if (getLog().isDebugEnabled()) {
                            getLog().debug(
                                "CGI request failed: "
                                    + exception.getMessage());
                        }
                    }

                    @Override public void onResponseReceived(
                            Request  request,
                            Response response)
                    {
                        String responseString = response.getText();

                        if (getLog().isDebugEnabled()) {
                            getLog().debug(
                                "CGI response received: " + responseString);
                        }

                        if (responseString.startsWith("Success")) {

                            // We're done!
                            Location.reload();
                        }
                        else {
                            SimpleErrorBox      error      = getUIFactory()
                                    .createSimpleErrorBox(
                                        "Error occurred during File Defect: "
                                        + responseString);
                            CommanderUrlBuilder urlBuilder = CommanderUrlBuilder
                                    .createUrl("jobDetails.php")
                                    .setParameter("jobId", jobId);

                            error.add(
                                new Anchor("(See job for details)",
                                    urlBuilder.buildString()));

                            if (getLog().isDebugEnabled()) {
                                getLog().debug(
                                    "Error occurred during File Defect");
                            }
                        }
                    }
                });
        }
        catch (RequestException e) {

            if (getLog().isDebugEnabled()) {
                getLog().debug("CGI request failed: " + e.getMessage());
            }
        }
    }
}
