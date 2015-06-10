
// Reports.java --
//
// Reports.java is part of ElectricCommander.
//
// Copyright (c) 2005-2012 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import com.google.gwt.core.client.GWT;
import com.google.gwt.safehtml.client.SafeHtmlTemplates;
import com.google.gwt.safehtml.shared.SafeHtml;
import org.jetbrains.annotations.NonNls;

import com.google.gwt.user.client.ui.DecoratorPanel;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.PropertySheet;
import com.electriccloud.commander.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.PropertySheetCallback;
import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.protocol.xml.RequestSerializerImpl;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createUrl;

/**
 */
public class Reports
    extends ComponentBase
{

    //~ Static fields/initializers ---------------------------------------------

    private static final ReportTemplates TEMPLATES = GWT.create(ReportTemplates.class);

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {

        /* Renders the component. */
        DecoratorPanel rootPanel = new DecoratorPanel();
        VerticalPanel  vPanel    = new VerticalPanel();
        //getLog().setLogLevel(Log.LogLevel.DEBUG);

        vPanel.setBorderWidth(0);

        String              jobId      = getGetParameter("jobId");
        CommanderUrlBuilder urlBuilder = createUrl("jobDetails.php")
                .setParameter("jobId", jobId);

        Widget htmlH1 = new HTML("<h1>Changelog</h1>");

        vPanel.add(htmlH1);

        Widget htmlLabel = new HTML(TEMPLATES.buildJobLink(
                "Repo Changelog associated with the ElectricCommander Job:", jobId, urlBuilder.buildString()));

        vPanel.add(htmlLabel);

        FormTable formTable = getUIFactory().createFormTable();

        callback("ecscm_changeLogs", formTable);
        vPanel.add(formTable.getWidget());
        rootPanel.add(vPanel);

        return rootPanel;
    }

    private void callback(
            @NonNls String  propertyName,
            final FormTable formTable)
    {
        String jobId = getGetParameter("jobId");

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
                "Reports doInit: setting up getProperties command request");
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

                    // noinspection HardCodedStringLiteral
                    formTable.addRow("0", new Label("No changelogs Found"));
                }
            });

        if (getLog().isDebugEnabled()) {
            getLog().debug("Reports doInit: Issuing Commander request: "
                    + new RequestSerializerImpl().serialize(req));
        }

        doRequest(req);
    }

    private void parseResponse(
            PropertySheet response,
            FormTable     form)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug("getProperties request returned "
                    + response.getProperties()
                              .size() + " properties");
        }
        Map<String, Property> propertiesMap = response.getProperties();
        final String PREFLIGHT_UPDATES = "Preflight Updates";
        boolean isPreflightChangeLog = propertiesMap.containsKey(PREFLIGHT_UPDATES);
        if (isPreflightChangeLog) {
            Property property = propertiesMap.get(PREFLIGHT_UPDATES);
            HTML html = new HTML (TEMPLATES.changeLog(PREFLIGHT_UPDATES, getPreflightUpdatesAsHtml(property.getValue())));
            form.addRow("0", html);
        } else {
            Collection<Property> properties = propertiesMap.values();
            for (Property p : properties) {
                HTML html = new HTML (TEMPLATES.changeLog(p.getName(), getChangeLogAsHtml(p.getValue())));
                form.addRow("0", html);

                if (getLog().isDebugEnabled()) {
                    getLog().debug("  propertyName="
                            + p.getName()
                            + ", value=" + p.getValue());
                }
            }
        }
    }

    private SafeHtml getChangeLogAsHtml(String value) {
        String[] lines = value.split("\n");

        String currentProject = "";//Defaulting to empty string in case there is no project log
        boolean wasInHeader = false;
        SafeHtml changeLogHTML = null;

        for (String line: lines) {

            SafeHtml lineHTML = null;
            if (isProjectHeader(line)) {
                currentProject = extractProject(line);
                wasInHeader = false;
            } else if (isHeader(line)) {
                lineHTML = TEMPLATES.commitLogHeader(line);
                if (!wasInHeader) {
                    SafeHtml projectHTML = TEMPLATES.projectHeader(currentProject);
                    lineHTML = TEMPLATES.htmlSnippet(projectHTML, lineHTML);
                    wasInHeader = true;
                }
            } else {
                lineHTML = TEMPLATES.commitLogContent(line);
                wasInHeader = false;
            }

            if (lineHTML != null) {
                changeLogHTML = changeLogHTML == null ? lineHTML : TEMPLATES.htmlSnippet(changeLogHTML, lineHTML);
            }

        }
        return changeLogHTML;
    }

    private SafeHtml getPreflightUpdatesAsHtml(String value) {
        String[] lines = value.split("\n");

        String currentProject = "";//Defaulting to empty string in case there is no project log
        List<String> headers = new ArrayList<String>();
        boolean wasProjectLine = false;
        SafeHtml changeLogHTML = null;

        for (String line: lines) {

            SafeHtml lineHTML = null;
            if (isProjectHeader(line)) {
                currentProject = extractProject(line);
                wasProjectLine = true;
            } else if (isHeader(line)) {
                //The preflight changelog comes with the header lines (Author only as of now)
                //before the project line. So we cache the header till we encounter a
                //standard content line following the project header.
                headers.add(line);
            } else {
                lineHTML = TEMPLATES.commitLogContent(line);
                if (wasProjectLine) {
                    SafeHtml projectHTML = TEMPLATES.projectHeader(currentProject);
                    projectHTML = appendHeaders(projectHTML, headers);
                    lineHTML = TEMPLATES.htmlSnippet(projectHTML, lineHTML);
                }
                wasProjectLine = false;
            }

            if (lineHTML != null) {
                changeLogHTML = changeLogHTML == null ? lineHTML : TEMPLATES.htmlSnippet(changeLogHTML, lineHTML);
            }

        }
        return changeLogHTML;
    }

    private SafeHtml appendHeaders(SafeHtml projectHTML, List<String> headers) {
        for (String header: headers) {
            SafeHtml lineHTML = TEMPLATES.commitLogHeader(header);
            projectHTML = TEMPLATES.htmlSnippet(projectHTML, lineHTML);
        }
        return projectHTML;
    }

    private String extractProject(String line) {
        //Remove leading 'project ' and trailing '/' or '\' for file path separator
        String project = line.substring("project ".length(), line.length());
        if (project.endsWith("/") || project.endsWith("\\")) {
            project = project.substring(0, project.length() -1);
        }
        return project;
    }

    private boolean isProjectHeader(String line) {
        return line.startsWith("project ");
    }

    private boolean isHeader(String line) {
        //This is based on the assumption that we are using the
        //pretty=format:Revision\:\ %H%nAuthor\:\ %an<%ae>\ on\ %aD%nCommitter\:\ %cn<%ce>\ on\ %cD%n%n\ %s%n %b%n
        //with git log
        return line.startsWith("Revision: ") ||
                line.startsWith("Author: ") ||
                line.startsWith("Committer: ");
    }

    //~ Inner Interfaces -------------------------------------------------------

    interface ReportTemplates
            extends SafeHtmlTemplates {

        //~ Methods ------------------------------------------------------------
        @SafeHtmlTemplates.Template("<h2>{0}</h2>{1}")
        SafeHtml changeLog(
                String  heading,
                SafeHtml changeLogSummary);

        @SafeHtmlTemplates.Template("<hr/><table><tr><td><b>Project: {0}</b></td></tr></table>")
        SafeHtml projectHeader(
                String   text);

        @SafeHtmlTemplates.Template("<table><tr><td><b>{0}</b></td></tr></table>")
        SafeHtml commitLogHeader(
                String   text);

        @SafeHtmlTemplates.Template("<table><tr><td>&nbsp;&nbsp;{0}</td></tr></table>")
        SafeHtml commitLogContent(
                String   text);

        @SafeHtmlTemplates.Template("{0}{1}")
        SafeHtml htmlSnippet(SafeHtml block1, SafeHtml block2);


        @SafeHtmlTemplates.Template("<h2>{0} <a href=\"{2}\">{1}</a></h2>")
        SafeHtml buildJobLink(String label, String jobId, String uri);

    }
}
