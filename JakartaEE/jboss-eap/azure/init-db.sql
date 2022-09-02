use `checklist`;

--
-- Table structure for table `checklist`
--

DROP TABLE IF EXISTS `checklist`;
CREATE TABLE `checklist` (
  `ID` int NOT NULL AUTO_INCREMENT,
  `name` char(35) NOT NULL DEFAULT '',
  `date` datetime not null,
  `description` char(75) NULL DEFAULT '',
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `checkitem`;
CREATE TABLE `checkitem` (
  `ID` int NOT NULL AUTO_INCREMENT,
  `checklist_ID` int NOT NULL DEFAULT '0',
  `description` char(75) NULL DEFAULT '',
  PRIMARY KEY (`ID`),
  CONSTRAINT `checkitem_clfk_1` FOREIGN KEY (`checklist_ID`) REFERENCES `checklist` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;