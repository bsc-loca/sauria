VCD_FILE=$1
WAVE_FILE=$2

if [ -z "$VCD_FILE" ]
then
      echo "No VCD file passed. Please use the script as:"
      echo "source display_vcd_waves.sh tracename.vcd wavecfg.gtkw"
      echo ""
      echo "Aborting."
      return 0
fi

if [ -z "$WAVE_FILE" ]
then
      echo "No wave configuration file passed. Opening GTKWave without configuring."
      echo ""
fi

SIGNALS_FONTSIZE=13
WAVES_FONTSIZE=13

gtkwave -A --g --rcvar "fontname_signals Monospace $SIGNALS_FONTSIZE" --rcvar "fontname_waves Monospace $WAVES_FONTSIZE" $VCD_FILE $WAVE_FILE