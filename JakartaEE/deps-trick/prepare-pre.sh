PRE_CLASSPATH=""
for f in /u01/azure-mysql-passwordless/*.jar; do
    PRE_CLASSPATH=${PRE_CLASSPATH}":"$f
done
echo $PRE_CLASSPATH