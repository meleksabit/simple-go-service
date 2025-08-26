FROM jenkins/jenkins:2.516.2-lts-jdk21

USER root
RUN apt-get update && apt-get install -y curl jq && rm -rf /var/lib/apt/lists/*

# Preinstall plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Bake in JCasC configs
COPY casc_configs/ /usr/share/jenkins/ref/casc_configs/

# Fix permissions explicitly to avoid AccessDeniedException
RUN chown -R jenkins:jenkins /usr/share/jenkins/ref/casc_configs \
    && chmod -R 755 /usr/share/jenkins/ref/casc_configs

# Point Jenkins Configuration as Code to the baked-in directory
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc_configs

USER jenkins
